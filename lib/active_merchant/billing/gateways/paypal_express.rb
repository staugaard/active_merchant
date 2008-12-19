require File.dirname(__FILE__) + '/paypal/paypal_common_api'
require File.dirname(__FILE__) + '/paypal/paypal_express_response'
require File.dirname(__FILE__) + '/paypal_express_common'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PaypalExpressGateway < Gateway
      include PaypalCommonAPI
      include PaypalExpressCommon
      
      self.test_redirect_url = 'https://www.sandbox.paypal.com/cgi-bin/webscr'
      self.supported_countries = ['US']
      self.homepage_url = 'https://www.paypal.com/cgi-bin/webscr?cmd=xpt/merchant/ExpressCheckoutIntro-outside'
      self.display_name = 'PayPal Express Checkout'
      
      def setup_authorization(money, options = {})
        requires!(options, :return_url, :cancel_return_url)
        
        commit 'SetExpressCheckout', build_setup_request('Authorization', money, options)
      end
      
      def setup_purchase(money, options = {})
        requires!(options, :return_url, :cancel_return_url)
        
        commit 'SetExpressCheckout', build_setup_request('Sale', money, options)
      end
      
      def setup_recurring(options = {})
        requires!(options, :return_url, :cancel_return_url, :description)
        
        commit 'SetCustomerBillingAgreement', build_setup_recurring_payment_request(options)
      end

      def details_for(token)
        commit 'GetExpressCheckoutDetails', build_get_details_request(token)
      end

      def details_for_recurring(token)
        commit 'GetBillingAgreementCustomerDetails', build_get_recurring_details_request(token)
      end

      def authorize(money, options = {})
        requires!(options, :token, :payer_id, :description)
      
        commit 'DoExpressCheckoutPayment', build_sale_or_authorization_request('Authorization', money, options)
      end

      def purchase(money, options = {})
        requires!(options, :token, :payer_id)
        
        commit 'DoExpressCheckoutPayment', build_sale_or_authorization_request('Sale', money, options)
      end
      
      def recurring(money, options = {})
        requires!(options, :token, :period)

        commit 'CreateRecurringPaymentsProfile', build_create_recurring_payment_profile_request(money, options)
      end
      
      def recurring_inquiry(profile_id, options = {})
        commit 'GetRecurringPaymentsProfileDetails', build_get_recurring_payment_profile_details_request(profile_id)
      end   

      def cancel_recurring(profile_id, options = {})
        commit 'ManageRecurringPaymentsProfileStatus', build_manage_recurring_payment_profile_status_request(profile_id, :cancel, options)
      end

      private
      def build_get_details_request(token)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'GetExpressCheckoutDetailsReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'GetExpressCheckoutDetailsRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'Token', token
          end
        end

        xml.target!
      end
      
      def build_get_recurring_details_request(token)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'GetBillingAgreementCustomerDetailsReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'GetBillingAgreementCustomerDetailsRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'Token', token
          end
        end

        xml.target!
      end
      
      def build_sale_or_authorization_request(action, money, options)
        currency_code = options[:currency] || currency(money)
        
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'DoExpressCheckoutPaymentReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'DoExpressCheckoutPaymentRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:DoExpressCheckoutPaymentRequestDetails' do
              xml.tag! 'n2:PaymentAction', action
              xml.tag! 'n2:Token', options[:token]
              xml.tag! 'n2:PayerID', options[:payer_id]
              xml.tag! 'n2:PaymentDetails' do
                xml.tag! 'n2:OrderTotal', amount(money), 'currencyID' => currency_code
                
                # All of the values must be included together and add up to the order total
                if [:subtotal, :shipping, :handling, :tax].all?{ |o| options.has_key?(o) }
                  xml.tag! 'n2:ItemTotal', amount(options[:subtotal]), 'currencyID' => currency_code
                  xml.tag! 'n2:ShippingTotal', amount(options[:shipping]),'currencyID' => currency_code
                  xml.tag! 'n2:HandlingTotal', amount(options[:handling]),'currencyID' => currency_code
                  xml.tag! 'n2:TaxTotal', amount(options[:tax]), 'currencyID' => currency_code
                end
                
                xml.tag! 'n2:NotifyURL', options[:notify_url]
                xml.tag! 'n2:ButtonSource', application_id.to_s.slice(0,32) unless application_id.blank?
              end
            end
          end
        end

        xml.target!
      end
      
      def build_setup_request(action, money, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'SetExpressCheckoutReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'SetExpressCheckoutRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:SetExpressCheckoutRequestDetails' do
              xml.tag! 'n2:PaymentAction', action
              xml.tag! 'n2:OrderTotal', amount(money).to_f.zero? ? amount(100) : amount(money), 'currencyID' => options[:currency] || currency(money)
              if options[:max_amount]
                xml.tag! 'n2:MaxAmount', amount(options[:max_amount]), 'currencyID' => options[:currency] || currency(options[:max_amount])
              end
              add_address(xml, 'n2:Address', options[:shipping_address] || options[:address])
              xml.tag! 'n2:AddressOverride', options[:address_override] ? '1' : '0'
              xml.tag! 'n2:NoShipping', options[:no_shipping] ? '1' : '0'
              xml.tag! 'n2:ReturnURL', options[:return_url]
              xml.tag! 'n2:CancelURL', options[:cancel_return_url]
              xml.tag! 'n2:IPAddress', options[:ip]
              xml.tag! 'n2:OrderDescription', options[:description]
              xml.tag! 'n2:BuyerEmail', options[:email] unless options[:email].blank?
              xml.tag! 'n2:InvoiceID', options[:order_id]
        
              # Customization of the payment page
              xml.tag! 'n2:PageStyle', options[:page_style] unless options[:page_style].blank?
              xml.tag! 'n2:cpp-image-header', options[:header_image] unless options[:header_image].blank?
              xml.tag! 'n2:cpp-header-back-color', options[:header_background_color] unless options[:header_background_color].blank?
              xml.tag! 'n2:cpp-header-border-color', options[:header_border_color] unless options[:header_border_color].blank?
              xml.tag! 'n2:cpp-payflow-color', options[:background_color] unless options[:background_color].blank?
              
              xml.tag! 'n2:LocaleCode', options[:locale] unless options[:locale].blank?
            end
          end
        end

        xml.target!
      end
      
      #RECURRING PAYMENTS REQUESTS
      
      def build_setup_recurring_payment_request(options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'SetCustomerBillingAgreementReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'SetCustomerBillingAgreementRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:SetCustomerBillingAgreementRequestDetails' do
              xml.tag! 'n2:BillingAgreementDetails' do
                xml.tag! 'n2:BillingType', 'RecurringPayments'
                xml.tag! 'n2:BillingAgreementDescription', options[:description]
              end
              xml.tag! 'n2:ReturnURL', options[:return_url]
              xml.tag! 'n2:CancelURL', options[:cancel_return_url]
              xml.tag! 'n2:LocaleCode', options[:locale] unless options[:locale].blank?
              xml.tag! 'n2:BuyerEmail', options[:email] unless options[:email].blank?
              
              # Customization of the payment page
              xml.tag! 'n2:PageStyle', options[:page_style] unless options[:page_style].blank?
              xml.tag! 'n2:cpp-image-header', options[:header_image] unless options[:header_image].blank?
              xml.tag! 'n2:cpp-header-back-color', options[:header_background_color] unless options[:header_background_color].blank?
              xml.tag! 'n2:cpp-header-border-color', options[:header_border_color] unless options[:header_border_color].blank?
              xml.tag! 'n2:cpp-payflow-color', options[:background_color] unless options[:background_color].blank?
              
            end
          end
        end

        xml.target!
      end
      
      def build_create_recurring_payment_profile_request(money, options)
        currency_code = options[:currency] || currency(money)

        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'CreateRecurringPaymentsProfileReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'CreateRecurringPaymentsProfileRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:CreateRecurringPaymentsProfileRequestDetails' do
              xml.tag! 'n2:Token', options[:token]
              
              xml.tag! 'n2:RecurringPaymentsProfileDetails' do
                xml.tag! 'n2:SubscriberName', options[:subscriber_name] unless options[:subscriber_name].blank?
                xml.tag! 'n2:BillingStartDate', (options[:start_date] || Time.now).to_time.utc.iso8601
                xml.tag! 'n2:ProfileReference', options[:reference] unless options[:reference].blank?
              end
              
              xml.tag! 'n2:ScheduleDetails' do
                xml.tag! 'n2:Description', options[:description]
                xml.tag! 'n2:PaymentPeriod' do
                  xml.tag! 'n2:BillingPeriod', options[:period].to_s.camelize
                  xml.tag! 'n2:BillingFrequency', options[:frequency].blank? ? 1 : options[:frequency].to_i
                  xml.tag! 'n2:Amount', amount(money), 'currencyID' => currency_code
                  xml.tag! 'n2:TaxAmount', amount(options[:tax]), 'currencyID' => currency_code if options[:tax]
                end
                xml.tag! 'n2:MaxFailedPayments', options[:max_failed_payments] unless options[:max_failed_payments].blank?
              end
            end
          end
        end

        xml.target!
      end

      def build_get_recurring_payment_profile_details_request(profile_id)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'GetRecurringPaymentsProfileDetailsReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'GetRecurringPaymentsProfileDetailsRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'ProfileID', profile_id
          end
        end
      
        xml.target!
      end
      
      def build_manage_recurring_payment_profile_status_request(profile_id, action, options)
        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'ManageRecurringPaymentsProfileStatusReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'ManageRecurringPaymentsProfileStatusRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:ManageRecurringPaymentsProfileStatusRequestDetails' do
              xml.tag! 'n2:ProfileID', profile_id
              xml.tag! 'n2:Action', action.to_s.camelize
              xml.tag! 'n2:Note', options[:note].strip unless options[:note].blank?
            end
          end
        end

        xml.target!
      end
      
      def build_bill_outstanding_amount_request(profile_id, money = nil)
        currency_code = options[:currency] || currency(money)

        xml = Builder::XmlMarkup.new :indent => 2
        xml.tag! 'BillOutstandingAmountReq', 'xmlns' => PAYPAL_NAMESPACE do
          xml.tag! 'BillOutstandingAmountRequest', 'xmlns:n2' => EBAY_NAMESPACE do
            xml.tag! 'n2:Version', API_VERSION
            xml.tag! 'n2:BillOutstandingAmountRequestDetails' do
              xml.tag! 'n2:ProfileID', profile_id
              xml.tag! 'n2:Amount', amount(money), 'currencyID' => currency_code unless money.nil?
            end
          end
        end

        xml.target!
      end
      
      def build_response(success, message, response, options = {})
        PaypalExpressResponse.new(success, message, response, options)
      end
    end
  end
end
