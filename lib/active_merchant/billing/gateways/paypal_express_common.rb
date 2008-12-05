module ActiveMerchant
  module Billing
    module PaypalExpressCommon
      def self.included(base)
        base.cattr_accessor :test_redirect_url
        base.cattr_accessor :live_redirect_url
        base.live_redirect_url = 'https://www.paypal.com/cgibin/webscr'
      end
      
      def redirect_url
        test? ? test_redirect_url : live_redirect_url
      end
      
      def redirect_url_for(token, options = {})
        options = {:review => true, :cmd => '_express-checkout'}.update(options)
        url = "#{redirect_url}?cmd=#{options[:cmd]}&token=#{token}"
        url << "&useraction=commit" unless options[:review]
        url
      end
    end
  end
end