require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class MaxipagoGateway < Gateway
      API_VERSION = '3.1.1.15'

      self.live_url = 'https://api.maxipago.net/UniversalAPI/postXML'

      self.test_url = 'https://testapi.maxipago.net/UniversalAPI/postXML'

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['BR']
      self.default_currency = 'BRL'
      self.money_format = :dollars

      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master, :discover, :american_express, :diners_club]

      # The homepage URL of the gateway
      self.homepage_url = 'http://www.maxipago.com/'

      # The name of the gateway
      self.display_name = 'maxiPago!'

      def initialize(options = {})
        requires!(options, :login, :password)
        super
      end

      def authorize(money, creditcard, options = {})
        post = {action: 'auth'}
        add_aux_data(post, options)
        add_amount(post, money)
        add_creditcard(post, creditcard)
        add_name(post, creditcard)
        add_address(post, options)
        #add_customer_data(post, options)

        commit('authonly', money, post)
      end

      def purchase(money, creditcard, options = {})
        post = {action: 'sale'}
        add_aux_data(post, options)
        add_amount(post, money)
        add_creditcard(post, creditcard)
        add_name(post, creditcard)
        add_address(post, options)
        #add_customer_data(post, options)

        commit('sale', money, post)
      end

      def capture(money, authorization, options = {})
        post = {orderID: authorization}
        add_amount(post, money)
        add_aux_data(post, options)
        commit('capture', money, post)
      end

      def prepaid_voucher(money, options = {})
        post = {}
        post[:billing_name] = options[:billing_address][:name]
        post[:referenceNum] = options[:order_id]
        post[:nosso_numero] = options[:nosso_numero]
        add_amount(post, money)
        add_address(post, options)
        commit('voucher', money, post)
      end

      private

      def commit(action, money, parameters)
        url = test? ? self.test_url : self.live_url
        request = self.send("build_#{action}_request", parameters)
        raw_response = ssl_post(url, request, 'Content-Type' => 'text/xml')
        response = parse(raw_response)
        Response.new(
          success?(response),
          message_from(response),
          response,
          test: test?,
          authorization: response[:order_id]
        )
      end

      def success?(response)
        response[:response_code] == '0'
      end

      def message_from(response)
        return response[:error_message] if response[:error_message].present?
        return response[:processor_message] if response[:processor_message].present?
        return response[:response_message] if response[:response_message].present?
        return success?(response) ? 'success' : 'error'
      end

      def add_aux_data(post, options)
        post[:processorID] = test? ? 1 : 4 # test: 1, redecard: 2, cielo: 4
        post[:referenceNum] = options[:order_id]
      end

      def add_amount(post, money)
        post[:amount] = amount(money)
      end

      def add_creditcard(post, creditcard)
        post[:card_number] = creditcard.number
        post[:card_exp_month] = creditcard.month
        post[:card_exp_year] = creditcard.year
        post[:card_cvv] = creditcard.verification_value
      end

      def add_name(post, creditcard)
        post[:billing_name] = creditcard.name
      end

      def add_address(post, options)
        post[:billing_address] = options[:billing_address][:address1]
        post[:billing_address2] = options[:billing_address][:address2]
        post[:billing_city] = options[:billing_address][:city]
        post[:billing_state] = options[:billing_address][:state]
        post[:billing_postalcode] = options[:billing_address][:zip]
        post[:billing_country] = options[:billing_address][:country]
        post[:billing_phone] = options[:billing_address][:phone]
      end

      def build_capture_request(params)
        build_request(params) do |xml|
          xml.capture! {
            xml.orderID params[:orderID]
            xml.referenceNum params[:referenceNum] # spree_order
            xml.payment {
              xml.chargeTotal params[:amount]
            }
          }
        end
      end

      def build_authonly_request(params)
        build_request(params) do |xml|
          xml.send(params[:action]) {
            xml.processorID params[:processorID]
            xml.fraudCheck 'N'
            xml.referenceNum params[:referenceNum] # spree_order
            xml.transactionDetail {
              xml.payType {
                xml.creditCard {
                  xml.number params[:card_number]
                  xml.expMonth params[:card_exp_month]
                  xml.expYear params[:card_exp_year]
                  xml.cvvNumber params[:card_cvv]
                }
              }
            }
            xml.payment {
              xml.chargeTotal params[:amount]
            }
            xml.billing {
              xml.name params[:billing_name]
              xml.address params[:billing_address] if params[:billing_address].present?
              xml.address2 params[:billing_address2] if params[:billing_address2].present?
              xml.city params[:billing_city] if params[:billing_city].present?
              xml.state params[:billing_state] if params[:billing_state].present?
              xml.postalcode params[:billing_postalcode] if params[:billing_postalcode].present?
              xml.country params[:billing_country] if params[:billing_country].present?
              xml.phone params[:billing_phone] if params[:billing_phone].present?
            }
          }
        end
      end
      alias_method :build_sale_request, :build_authonly_request

      def build_voucher_request(params)
        build_request(params) do |xml|
          xml.sale {
            xml.processorID '12' # Bradesco
            xml.referenceNum params[:referenceNum] # spree_order
            xml.billing {
              xml.name params[:billing_name] # add_name
              xml.address params[:billing_address] if params[:billing_address].present?
              xml.address2 params[:billing_address2] if params[:billing_address2].present?
              xml.city params[:billing_city] if params[:billing_city].present?
              xml.state params[:billing_state] if params[:billing_state].present?
              xml.postalcode params[:billing_postalcode] if params[:billing_postalcode].present?
              xml.country params[:billing_country] if params[:billing_country].present?
              xml.phone params[:billing_phone] if params[:billing_phone].present?
            }
            xml.transactionDetail {
              xml.payType {
                xml.boleto {
                  xml.expirationDate I18n.l(Date.current + 7.days, format: '%Y-%m-%d')
                  xml.number params[:nosso_numero]
                  xml.instructions 'Sr. Caixa, nao aceitar apos o vencimento.'
                }
              }
            }
            xml.payment {
              xml.chargeTotal params[:amount]
            }
          }
        end
      end

      def build_request(params)
        builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
          xml.send("transaction-request") {
            xml.version API_VERSION
            xml.verification {
              xml.merchantId @options[:login]
              xml.merchantKey @options[:password]
            }
            xml.order {
              yield(xml)
            }
          }
        end
        builder.to_xml(indent: 2)
      end

      def parse(body)
        xml = REXML::Document.new(body)

        response = {}
        xml.root.elements.to_a.each do |node|
          parse_element(response, node)
        end
        response
      end

      def parse_element(response, node)
        if node.has_elements?
          node.elements.each{|element| parse_element(response, element) }
        else
          response[node.name.underscore.to_sym] = node.text
        end
      end

    end
  end
end

