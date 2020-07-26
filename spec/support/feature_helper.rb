module Feature
  include Capybara::DSL

  module ValidUserRequestHelper
    # Signs in a valid user using the page.drive.post method
    def sign_in_as_reader
      @user ||= FactoryBot.create(:read_user)
      page.driver.post user_session_path, :user => {:email => @user.username, :password => @user.password}
    end
  end

  module LoginPage
    def visit_root
      visit root_path
      self
    end

    def login(user)
      fill_in 'user_username', with: user.username
      fill_in 'user_password', with: user.password
      click_on '登录'
    end
  end

  module DomOperate
    module Ivu
      # 选择ivu-select的数据项
      def select_item(selector, select_value = nil)
        find("#{selector} .ivu-select-selection")
        find("#{selector} .ivu-select-selection").click()
        wait_for_ajax
        if select_value
          all('li.ivu-select-item', :text => select_value)
          sleep(0.5)
          all('li.ivu-select-item', :text => select_value).first.click()
        else
          all('li.ivu-select-item')
          sleep(0.5)
          all('li.ivu-select-item').last.click()
        end
        sleep(0.5)
      end

      def select_date(selector, date)
        # 显示日期选择界面 需将DatePicker的ref设置为与id一致，使用驼峰命名
        page.execute_script("window.vueInstance.$refs.#{selector.gsub('#', '')}.visible=true")
        within("#{selector} .ivu-select-dropdown") do
          all_enabled = all("#{selector} .ivu-date-picker-cells-cell:not(.ivu-date-picker-cells-cell-disabled)")
          selected = false
          all_enabled.each do |item|
            date = date.split('-').last
            if item.text == date
              item.click()
              selected = true
            end
          end
          all_enabled.first.click() unless selected
        end
        page.execute_script("window.vueInstance.$refs.#{selector.gsub('#', '')}.visible=false")
        sleep(0.5)
      end

      def click_ivu_modal_ok
        all('.ivu-modal', :visible => true)
        within('.ivu-modal') do
          click_on('确定')
        end
      end

      def click_ivu_checkbox(selector = nil)
        checkbox = all("#{selector} .ivu-checkbox").first
        checkbox.click()
      end

      def field_value_invalid?(selector)
        return find(selector)['aria-invalid'] == 'true'
      end

      def expect_ivu_select_item_count(selector, count)
        find("#{selector}").click()
        all("#{selector} .ivu-select-item", count: count)
        find("#{selector}").click()
      end

      def expect_ivu_msg(text)
        assert_selector(".ivu-message-notice-content", text: text)
      end

      def except_field_valid(selector)
        expect(field_value_invalid?(selector)).to eq false
      end

      def except_field_invalid(selector)
        expect(field_value_invalid?(selector)).to eq true
      end

      def except_fields_invalid(selector_id_list)
        selector_id_list.each do |item|
          except_field_invalid(item.include?('#') ? item : "##{item}")
        end
      end
    end

    module Normal
      def close_modal
        find('.modal-header .close').click()
      end

      def fill_good_form_with(good_params)
        within('#new_goods_form') do
          find_input_by_name('good[title]').set(good_params[:title])
          parts = good_params[:specification].split('x')
          find_input_by_name('good[length]').set(parts[0])
          find_input_by_name('good[width]').set(parts[1])
          find_input_by_name('good[height]').set(parts[2])
          find_input_by_name('good[quantity]').set(good_params[:quantity])
          select_item('#good_unit', '件')
          find_input_by_name('good[volume]').set(good_params[:volume])
          find_input_by_name('good[weight]').set(good_params[:weight])
        end
      end

      def click_bootbox_ok
        sleep(0.5)
        within '.bootbox' do
          click_on('OK')
        end
      end

      def find_input_by_name(name, options = {})
        find("input[name='#{name}']", options)
      end

      def click_btn(text)
        btn = all('a', text: text).first || all('button', text: text).first
        if btn
          btn.click()
        else
          all('.btn', text: text).first.click()
        end
      end
    end
  end

  module Utils
    def wait_for_ajax
      counter = 0
      while page.execute_script("return $.active").to_i > 0
        counter += 1
        sleep(0.1)
        raise "AJAX request took longer than 5 seconds." if counter >= 50
      end
    end

    def expect_h1_with_text(text)
      assert_selector('.content-header h1', text: text)
    end

    def expect_msg_modal_with_text(text)
      assert_selector('#msg-modal', visible: true)
      within('#msg-modal') do
        expect(page).to have_text(text)
      end
    end
  end
end