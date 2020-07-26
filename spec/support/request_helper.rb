module Requests
  include Warden::Test::Helpers

  # parse response.body to json
  module JsonHelpers
    def json
      JSON.parse(response.body)
    end
  end

  def self.included(base)
    base.before(:each) {Warden.test_mode!}
    base.after(:each) {Warden.test_reset!}
  end

  def sign_in(resource)
    login_as(resource, scope: warden_scope(resource))
  end

  def sign_out(resource)
    logout(warden_scope(resource))
  end

  def mock_authorize(controller_class, record, action = nil)
    if action
      allow_any_instance_of(controller_class).to receive(:authorize).with(record, action)
    else
      allow_any_instance_of(controller_class).to receive(:authorize).with(record)
    end
    allow_any_instance_of(controller_class).to receive(:verify_authorized)
  end

  private

  def warden_scope(resource)
    resource.class.name.underscore.to_sym
  end
end