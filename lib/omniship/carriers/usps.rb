# -*- encoding: utf-8 -*-
require 'cgi'

module Omniship
  class USPS < Carrier
    self.retry_safe = true

    cattr_reader :name

    def find_rates(origin, destination, package, options={})
      rates = []

      options[:services].each do |service_code, service_name|
        json = build_calculate_postage_rate_request(origin, destination, package, service_code, options)
        response = HTTParty.post "https://xpsship.rocksolidinternet.com/restapi/v1/customers/#{@options[:customer_id]}/quote",
                                 headers: {"Authorization" => "RSIS #{@options[:api_key]}", 'Content-Type' => 'application/json'},
                                 body: json.to_json
        res = JSON.parse(response.body)

        next unless res["totalAmount"].present?
        rates << RateEstimate.new(nil, nil, "USPS", service_code: service_code, service_name: service_name, total_price: res["totalAmount"].to_f)
      end

      success = rates.count > 0

      message = success ? nil : "There are no valid rates for this shipment!"

      RateResponse.new(success, message, {}, rates: rates)
    end

    def get_postage_label(origin, destination, package, options={})
      options = @options.merge(options)
      options[:label_size] ||= "4x6"
      options[:image_format] = "PDF"
      options[:image_resolution] ||= "600"
      options[:image_rotation] ||= "None"
      options[:service] ||= "First"

      json = build_book_shipment_request(origin, destination, package, options)

      response = HTTParty.post "https://xpsship.rocksolidinternet.com/restapi/v1/customers/#{@options[:customer_id]}/shipments",
                               headers: {"Authorization" => "RSIS #{@options[:api_key]}", 'Content-Type' => 'application/json'},
                               body: json.to_json
      res = JSON.parse(response.body)

      unless success?(response)
        response_hash = {}
        response_hash[:success] = false
        response_hash[:error_code] = res["errorCategory"]
        response_hash[:error_description] = res["error"]
        return response_hash
      end

      book_number = res["bookNumber"]
      tracking_number = res["trackingNumber"]
      charges = res["totalShippingCost"]

      response = HTTParty.get "https://xpsship.rocksolidinternet.com/restapi/v1/customers/#{@options[:customer_id]}/shipments/#{book_number}/label",
                  headers: {"Authorization" => "RSIS #{@options[:api_key]}"}

      if success?(response)
        response_hash = {}
        response_hash[:success] = true
        response_hash[:shipment_id] = tracking_number
        response_hash[:book_number] = book_number
        response_hash[:label] = response.body
      else
        response_hash = {}
        response_hash[:success] = false
        response_hash[:error_code] = res["errorCategory"]
        response_hash[:error_description] = res["error"]
      end

      response_hash
    end

    def get_refund(book_number, options = {})
      response = HTTParty.post "https://xpsship.rocksolidinternet.com/restapi/v1/customers/#{@options[:customer_id]}/shipments/#{book_number}",
                  headers: {"Authorization" => "RSIS #{@options[:api_key]}", 'Content-Type' => 'application/json'},
                  body: {voided: true}.to_json
      res = JSON.parse(response.body)

      if success?(response)
        response_hash = {}
        response_hash[:success] = true
      else
        response_hash = {}
        response_hash[:success] = false
        response_hash[:error_code] = res["errorCategory"] || "Uncategorized"
        response_hash[:error_description] = res["error"] || "Unknown USPS Refund Error"
      end

      response_hash
    end

    protected

      def success?(response)
        response.response.code.in?(['200', '201'])
      end


      def build_calculate_postage_rate_request(origin, destination, package, service_code, options = {})
        {
          carrierCode: "usps",
          serviceCode: service_code,
          packageTypeCode: package.options[:package_type] || "usps_custom_package",
          sender: {
            country: origin.country_code,
            zip: origin.zip
          },
          receiver: {
            country: destination.country_code,
            zip: destination.zip
          },
          residential: false,
          signatureOptionCode: nil,
          weightUnit: "lb",
          dimUnit: "in",
          currency: "USD",
          pieces: [package].map do |pack|
                    {
                      weight: pack.lbs.to_s,
                      length: pack.inches(:length).to_s,
                      width: pack.inches(:width).to_s,
                      height: pack.inches(:height).to_s,
                      insuranceAmount: nil,
                      declaredValue: (destination.country_code == 'US' ? nil : pack.options[:amount])
                    }
                  end
        }
      end







      def build_book_shipment_request(origin, destination, package, options = {})
        {
          carrierCode: "usps",
          serviceCode: options[:service],
          packageTypeCode: package.options[:package_type],
          shipmentDate: DateTime.now.strftime("%Y-%m-%d"),
          shipmentReference: options[:order_number] || "Custom",
          contentDescription: "",
          sender: {
            name: origin.name,
            company: origin.company_name || "",
            address1: origin.address1,
            address2: origin.address2,
            city: origin.city,
            state: origin.state,
            zip: origin.zip,
            country: origin.country_code,
            phone: origin.phone.present? ? origin.phone.gsub(/[(\- )]/, '') : nil
          },
          receiver: {
            name: destination.name,
            company: destination.company_name || "",
            address1: destination.address1,
            address2: destination.address2,
            city: destination.city,
            state: destination.state,
            zip: destination.zip,
            country: destination.country_code,
            phone: destination.phone.present? ? destination.phone.gsub(/[(\- )]/, '') : nil
          },
          residential: false,
          signatureOptionCode: nil,
          weightUnit: "lb",
          dimUnit: "in",
          currency: "USD",
          labelImageFormat: "PDF",
          pieces: [package].map do |pack|
                    {
                      weight: pack.lbs.to_s,
                      length: pack.inches(:length).to_s,
                      width: pack.inches(:width).to_s,
                      height: pack.inches(:height).to_s,
                      insuranceAmount: nil,
                      declaredValue: (destination.country_code == 'US' ? nil : pack.options[:amount])
                    }
                  end,
          approvePrepayRecharge: true
        }
      end
  end
end
