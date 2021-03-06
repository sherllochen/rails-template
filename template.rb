require "bundler"
require "json"
require "fileutils"
require "shellwords"
RAILS_REQUIREMENT = "~> 6.0.0".freeze

# 总入口
def apply_template!
  assert_minimum_rails_version
  assert_valid_options
  assert_postgresql
  add_template_repository_to_source_path

  template "Gemfile.tt", force: true

  template "README.md.tt", force: true
  remove_file "README.rdoc"

  template "example.env.tt"
  copy_file "editorconfig", ".editorconfig"
  copy_file "gitignore", ".gitignore", force: true
  copy_file "overcommit.yml", ".overcommit.yml"
  template "ruby-version.tt", ".ruby-version", force: true

  copy_file "Guardfile"
  copy_file "Procfile"

  apply "Rakefile.rb"
  apply "config.ru.rb"
  apply "app/template.rb"
  apply "bin/template.rb"
  apply "circleci/template.rb"
  apply "config/template.rb"
  apply "doc/template.rb"
  apply "lib/template.rb"
  apply "test/template.rb"

  git :init unless preexisting_git_repo?
  empty_directory ".git/safe"

  run_with_clean_bundler_env "bin/setup"
  setup_gems

  after_setup

  # run_with_clean_bundler_env "bin/rails webpacker:install"
  create_initial_migration
  generate_spring_binstubs

  binstubs = %w[
    annotate brakeman bundler bundler-audit guard rubocop sidekiq
    terminal-notifier rspec-core
  ]
  run_with_clean_bundler_env "bundle binstubs #{binstubs.join(' ')} --force"

  template "rubocop.yml.tt", ".rubocop.yml"
  run_rubocop_autocorrections

  template "eslintrc.js", ".eslintrc.js"
  template "prettierrc.js", ".prettierrc.js"
  add_eslint_and_run_fix
  add_javascript

  unless any_local_git_commits?
    say 'Git processing...'
    git add: "-A ."
    git commit: "-n -m 'Set up project'"
    if git_repo_specified?
      git remote: "add origin #{git_repo_url.shellescape}"
      git push: "-u origin --all"
    end
    say 'Git done.'
  end
end


# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("rails-template-"))
    at_exit {FileUtils.remove_entry(tempdir)}
    git clone: [
        "--quiet",
        "https://github.com/sherllochen/rails-template.git",
        tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{rails-template/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) {git checkout: branch}
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def rails_version
  @rails_version ||= Gem::Version.new(Rails::VERSION::STRING)
end

def assert_minimum_rails_version
  requirement = Gem::Requirement.new(RAILS_REQUIREMENT)
  return if requirement.satisfied_by?(rails_version)

  prompt = "This template requires Rails #{RAILS_REQUIREMENT}. "\
           "You are using #{rails_version}. Continue anyway?"
  exit 1 if no?(prompt)
end

# Bail out if user has passed in contradictory generator options.
def assert_valid_options
  valid_options = {
      skip_gemfile: false,
      skip_bundle: false,
      skip_git: false,
      skip_system_test: false,
      # skip_test: false,
      # skip_test_unit: false,
      edge: false
  }
  valid_options.each do |key, expected|
    next unless options.key?(key)
    actual = options[key]
    unless actual == expected
      fail Rails::Generators::Error, "Unsupported option: #{key}=#{actual}"
    end
  end
end

def assert_postgresql
  return if IO.read("Gemfile") =~ /^\s*gem ['"]pg['"]/
  fail Rails::Generators::Error, "This template requires PostgreSQL, but the pg gem isn’t present in your Gemfile."
end

def git_repo_url
  @git_repo_url ||=
      ask_with_default("What is the git remote URL for this project?", :blue, "skip")
end

def production_hostname
  @production_hostname ||=
      ask_with_default("Production hostname?", :blue, "example.com")
end

def gemfile_requirement(name)
  @original_gemfile ||= IO.read("Gemfile")
  req = @original_gemfile[/gem\s+['"]#{name}['"]\s*(,[><~= \t\d\.\w'"]*)?.*$/, 1]
  req && req.gsub("'", %(")).strip.sub(/^,\s*"/, ', "')
end

def ask_with_default(question, color, default)
  return default unless $stdin.tty?
  question = (question.split("?") << " [#{default}]?").join
  answer = ask(question, color)
  answer.to_s.strip.empty? ? default : answer
end

def git_repo_specified?
  git_repo_url != "skip" && !git_repo_url.strip.empty?
end

def preexisting_git_repo?
  @preexisting_git_repo ||= (File.exist?(".git") || :nope)
  @preexisting_git_repo == true
end

def any_local_git_commits?
  system("git log &> /dev/null")
end

def run_with_clean_bundler_env(cmd)
  success = if defined?(Bundler)
              if Bundler.respond_to?(:with_unbundled_env)
                Bundler.with_unbundled_env {run(cmd)}
              else
                Bundler.with_clean_env {run(cmd)}
              end
            else
              run(cmd)
            end
  unless success
    puts "Command failed, exiting: #{cmd}"
    exit(1)
  end
end

def run_rubocop_autocorrections
  run_with_clean_bundler_env "bin/rubocop -a --fail-level A > /dev/null || true"
end

def create_initial_migration
  return if Dir["db/migrate/**/*.rb"].any?
  run_with_clean_bundler_env "bin/rails generate migration initial_migration"
  run_with_clean_bundler_env "bin/rake db:migrate"
end

def add_eslint_and_run_fix
  say 'add_eslint_and_run_fix'
  packages = %w[
    babel-eslint
    eslint
    eslint-config-prettier
    eslint-plugin-jest
    eslint-plugin-prettier prettier
  ]
  run_with_clean_bundler_env "yarn add #{packages.join(' ')} -D"
  add_package_json_script(lint: "eslint 'app/javascript/**/*.{js,jsx}'")
  run_with_clean_bundler_env "yarn lint --fix"
end

def add_package_json_script(scripts)
  package_json = JSON.parse(IO.read("package.json"))
  package_json["scripts"] ||= {}
  scripts.each do |name, script|
    package_json["scripts"][name.to_s] = script
  end
  package_json = {
      "name" => package_json["name"],
      "scripts" => package_json["scripts"].sort.to_h
  }.merge(package_json)
  IO.write("package.json", JSON.pretty_generate(package_json) + "\n")
end

# 基础Gem配置
def setup_gems
  # run_with_clean_bundler_env "bundle install"
  run "bundle install"
  add_users
  add_rucaptcha
  add_sidekiq
  add_whenever
  add_sitemap
  add_rspec
  add_rswag
  add_bullet
end

def add_users
  say "Add Devise start...", :green
  # Install Devise
  generate "devise:install"

  # Configure Devise
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
              env: 'development'

  # generate :model, "User", "name:string"

  # Create Devise User
  generate :devise, "User", 'name'

  # add unique phone column
  generate 'migration add_phone_to_users phone:string:uniq'

  copy_file "app/models/user.rb", force: true
  copy_file "config/initializers/devise.rb", force: true
  say "Add Devise successfully", :green
end

def add_rspec
  say "Add Rspec start...", :green
  generate "rspec:install"
  copy_file ".rspec", force: true
  copy_file "spec/rails_helper.rb", force: true
  copy_file "spec/spec_helper.rb", force: true
  copy_file "spec/support/feature_helper.rb"
  copy_file "spec/support/global_helper.rb"
  copy_file "spec/support/request_helper.rb"
  say "Add Rspec successfully", :green
end

def add_rswag
  say "Add Rswag start...", :green
  generate "rswag:install"
  copy_file "lib/rswag_ui_csp.rb", force: true
  append_to_file "config/application.rb" do
    "require 'rswag_ui_csp'"
  end
  say "Add Rswag done", :green
end

def add_bullet
  insert_into_file "config/environments/development.rb", after: "Rails.application.configure do\n" do
    <<-'RUBY'
    # Bullet
    config.after_initialize do
      Bullet.enable = true
      # Bullet.sentry = true
      Bullet.alert = true
      Bullet.bullet_logger = true
      Bullet.console = true
      # Bullet.growl = true
      # Bullet.xmpp = { :account  => 'bullets_account@jabber.org',
      #                 :password => 'bullets_password_for_jabber',
      #                 :receiver => 'your_account@jabber.org',
      #                 :show_online_status => true }
      Bullet.rails_logger = true
      # Bullet.honeybadger = true
      # Bullet.bugsnag = true
      # Bullet.airbrake = true
      # Bullet.rollbar = true
      Bullet.add_footer = true
      Bullet.skip_html_injection = false
      # Bullet.stacktrace_includes = [ 'your_gem', 'your_middleware' ]
      # Bullet.stacktrace_excludes = [ 'their_gem', 'their_middleware', ['my_file.rb', 'my_method'], ['my_file.rb', 16..20] ]
      # Bullet.slack = { webhook_url: 'http://some.slack.url', channel: '#default', username: 'notifier' }
    end
    RUBY
  end
end

def add_rucaptcha
  copy_file "config/initializers/rucaptcha.rb"
end

def add_javascript
  say 'Add javascript'
  run "yarn add expose-loader jquery @popperjs/core bootstrap data-confirm-modal local-time"

  content = <<-JS
const webpack = require('webpack')
environment.plugins.append('Provide', new webpack.ProvidePlugin({
  $: 'jquery',
  jQuery: 'jquery',
  Rails: '@rails/ujs'
}))
  JS

  insert_into_file 'config/webpack/environment.js', content + "\n", before: "module.exports = environment"
  say 'Add javascript done.'
end

def add_sidekiq
  say 'Add sidekiq'
  environment "config.active_job.queue_adapter = :sidekiq"

  insert_into_file "config/routes.rb",
                   "require 'sidekiq/web'\n\n",
                   before: "Rails.application.routes.draw do"

  content = <<-RUBY
    # You must define a admin? method for user
    authenticate :user, lambda { |u| u.respond_to?(:admin?) && u.admin? } do
      mount Sidekiq::Web => '/sidekiq'
    end
  RUBY
  insert_into_file "config/routes.rb", "#{content}\n\n", after: "Rails.application.routes.draw do\n"
  say 'Add sidekiq done'
end

def add_whenever
  say 'Add whenever'
  run "wheneverize ."
  say 'Add whenever done'
end

def add_sitemap
  say 'Add sitemap'
  rails_command "sitemap:install"
  say 'Add sitemap done.'
end

def after_setup
  run "bin/yarn install" if File.exist?("yarn.lock")
  run "bundle exec overcommit --install"
  run "bin/rake tmp:create"
  run "bin/rake db:create"
  run "bin/rake db:migrate"
  run "bin/rake db:seed"
end

apply_template!
