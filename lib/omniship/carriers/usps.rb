# -*- encoding: utf-8 -*-
require 'cgi'

module Omniship
  class USPS < Carrier
    self.retry_safe = true

    cattr_reader :name

    DOMAINS = {
      true => 'https://elstestserver.endicia.com/LabelService/EwsLabelService.asmx?wsdl',
      false => ''
    }

    def requirements
      [:login]
    end

    def change_pass_phrase(options={})
      options = @options.merge(options)
      options[:test] ||= true
      options[:request_token] ||= false

      xml = build_change_pass_phrase_request(options)
      client = Savon.client(wsdl: DOMAINS[options[:test]])
      response = client.call :change_pass_phrase, xml: xml

      parse_change_pass_phrase_response(response.http.body)
    end

    def buy_postage(amount, options = {})
      options = @options.merge(options)
      options[:test] ||= true

      xml = build_buy_postage_request(amount, options)
      client = Savon.client(wsdl: DOMAINS[options[:test]])
      response = client.call :buy_postage, xml: xml

      parse_buy_postage_response(response.http.body)
    end

    def find_rates(origin, destination, package, options={})
      options = @options.merge(options)
      options[:test] ||= true

      xml = build_calculate_postage_rates_request(origin, destination, package, options)
      client = Savon.client(wsdl: DOMAINS[options[:test]])
      response = client.call :calculate_postage_rates, xml: xml

      parse_calculate_postage_rates_response(response.http.body)
    end

    def get_postage_label(origin, destination, package, options={})
      options = @options.merge(options)
      options[:test] ||= true
      options[:label_type] ||= destination.country_code == 'US' ? "Default" : "International"
      options[:label_subtype] ||= destination.country_code == 'US' ? nil : "Integrated"
      options[:label_size] ||= "4x6"
      options[:image_format] ||= "PNG"
      options[:image_resolution] ||= "600"
      options[:image_rotation] ||= "None"
      options[:service] ||= "First"

      xml = build_get_postage_label_request(origin, destination, package, options)
      client = Savon.client(wsdl: DOMAINS[options[:test]])
      response = client.call :get_postage_label, xml: xml

      parse_get_postage_label_response(response.http.body, options)
    end

    def get_refund(shipment_id, options = {})
      options = @options.merge(options)
      options[:test] ||= true

      xml = build_get_refund_request(shipment_id, options)
      client = Savon.client(wsdl: DOMAINS[options[:test]])
      response = client.call :get_refund, xml: xml

      parse_get_refund_response(response.http.body)
    end

    def valid_credentials?
      # Cannot test with find_rates because USPS doesn't allow that in test mode
      test_mode? ? canned_address_verification_works? : super
    end

    def maximum_weight
      Mass.new(70, :pounds)
    end

    protected

      def successful_response?(xml)
        xml.xpath('//Status').text == '0'
      end

      def build_change_pass_phrase_request(options = {})
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.send("soap:Envelope", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
                                    "xmlns:xsd" => "http://www.w3.org/2001/XMLSchema",
                                    "xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/") {
            xml.send("soap:Body") {
              xml.ChangePassPhrase(xmlns: "www.envmgr.com/LabelService") {
                xml.ChangePassPhraseRequest(TokenRequested: options[:request_token]) {
                  xml.RequesterID options[:test] ? 'lxxx' : options[:requester_id]
                  xml.RequestID "1" #Change this sometime later maybe...
                  xml.CertifiedIntermediary {
                    if options[:token].present?
                      xml.Token options[:token]
                    else
                      xml.AccountID options[:account_id]
                      xml.PassPhrase options[:old_phrase]
                    end

                  }
                  xml.NewPassPhrase options[:new_phrase]
                }
              }
            }
          }
        end
        builder.to_xml
      end

      def parse_change_pass_phrase_response(response)
        xml = Nokogiri::XML(response)
        xml.remove_namespaces!
        response_hash = {}
        response_hash[:response_code] = xml.xpath('//Status').text
        if successful_response?(xml)
          response_hash[:token] = xml.xpath('//Token').text if xml.xpath('//Token').present?
        else
          response_hash[:error_message] = xml.xpath("//ErrorMessage").text
        end
        response_hash
      end







      def build_buy_postage_request(amount, options = {})
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.send("soap:Envelope", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
                                    "xmlns:xsd" => "http://www.w3.org/2001/XMLSchema",
                                    "xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/") {
            xml.send("soap:Body") {
              xml.BuyPostage(xmlns: "www.envmgr.com/LabelService") {
                xml.RecreditRequest {
                  xml.RequesterID options[:test] ? 'lxxx' : options[:requester_id]
                  xml.RequestID "1" #Change this sometime later maybe...
                  xml.CertifiedIntermediary {
                    if options[:token].present?
                      xml.Token options[:token]
                    else
                      xml.AccountID options[:account_id]
                      xml.PassPhrase options[:old_phrase]
                    end
                  }
                  xml.RecreditAmount amount
                }
              }
            }
          }
        end
        builder.to_xml
      end

      def parse_buy_postage_response(response)
        xml = Nokogiri::XML(response)
        xml.remove_namespaces!
        response_hash = {}
        if xml.xpath('//ErrorMessage').present?
          response_hash[:error_description] = xml.xpath("//ErrorMessage").text
        else
          response_hash[:balance] = xml.xpath("//PostageBalance").text
        end
        response_hash
      end







      def build_calculate_postage_rates_request(origin, destination, package, options = {})
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.send("soap:Envelope", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
                                    "xmlns:xsd" => "http://www.w3.org/2001/XMLSchema",
                                    "xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/") {
            xml.send("soap:Body") {
              xml.CalculatePostageRates(xmlns: "www.envmgr.com/LabelService") {
                xml.PostageRatesRequest(ResponseVersion: "0") {
                  xml.RequesterID options[:test] ? 'lxxx' : options[:requester_id]
                  xml.CertifiedIntermediary {
                    if options[:token].present?
                      xml.Token options[:token]
                    else
                      xml.AccountID options[:account_id]
                      xml.PassPhrase options[:old_phrase]
                    end
                  }
                  xml.MailClass destination.country_code == 'US' ? "Domestic" : "International"
                  xml.WeightOz package.oz.round
                  xml.MailpieceShape "Parcel"
                  xml.MailpieceDimensions {
                    xml.Length package.inches(:length)
                    xml.Width package.inches(:width)
                    xml.Height package.inches(:height)
                  }
                  xml.FromCountryCode origin.country_code
                  xml.FromPostalCode origin.zip
                  xml.ToPostalCode destination.zip
                  xml.ToCountryCode destination.country_code
                }
              }
            }
          }
        end
        builder.to_xml
      end

      def parse_calculate_postage_rates_response(response)
        xml = Nokogiri::XML(response)
        xml.remove_namespaces!
        response_hash = {}
        response_hash[:response_code] = xml.xpath('//Status').text

        success = successful_response?(xml)
        message = xml.xpath("//ErrorMessage").text
        rate_estimates = []

        if success
          response_hash[:success] = true

          xml.xpath('//PostagePrice').each do |rated_shipment|
            service_code = rated_shipment.xpath('MailClass')[0].text
            service_name = rated_shipment.xpath('*/MailService')[0].text

            rate_estimates << RateEstimate.new(nil, nil, "USPS",
                                               service_code: service_code,
                                               service_name: service_name,
                                               total_price: rated_shipment['TotalAmount'].to_f)
          end
          response_hash[:rates] = rate_estimates
        else
          response_hash[:error_description] = message
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, rates: rate_estimates, xml: response)
      end









      def build_get_postage_label_request(origin, destination, package, options = {})
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.send("soap:Envelope", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
                                    "xmlns:xsd" => "http://www.w3.org/2001/XMLSchema",
                                    "xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/") {
            xml.send("soap:Body") {
              xml.GetPostageLabel(xmlns: "www.envmgr.com/LabelService") {
                xml.LabelRequest(Test: (options[:test] ? 'YES' : 'NO'), LabelType: options[:label_type], LabelSubtype: options[:label_subtype],
                                 LabelSize: options[:label_size], ImageFormat: options[:image_format],
                                 ImageResolution: options[:image_resolution], ImageRotation: options[:image_rotation]){
                  xml.RequesterID options[:test] ? 'lxxx' : options[:requester_id]
                  if options[:token].present?
                    xml.Token options[:token]
                  else
                    xml.AccountID options[:account_id]
                    xml.PassPhrase options[:passphrase]
                  end
                  xml.MailClass options[:service]
                  unless destination.country_code == 'US'
                    xml.CustomsCertify "TRUE"
                    xml.CustomsSigner "Bryan Killian" ##Maybe change...???
                    xml.CustomsSendersCopy "FALSE"
                    xml.CustomsInfo {
                      xml.ContentsType "Merchandise"
                      xml.CustomsItems {
                        xml.CustomsItem {
                          xml.Description "Uniforms and/or Apparel"
                          xml.Quantity 1
                          xml.Weight package.oz.round
                          xml.Value package.value / 100
                          xml.CountryOfOrigin 'US'
                        }
                      }
                    }
                  end
                  xml.WeightOz package.oz.round
                  xml.MailpieceShape package.options[:package_type]
                  xml.MailpieceDimensions {
                    xml.Length package.inches(:length)
                    xml.Width package.inches(:width)
                    xml.Height package.inches(:height)
                  }
                  xml.Description "Order##{options[:order_number]}" if options[:order_number].present?
                  xml.PartnerTransactionID "1"

                  xml.FromName origin.name if origin.name.present?
                  xml.FromCompany origin.company_name if origin.company_name.present?
                  xml.ReturnAddress1 origin.address1 if origin.address1.present?
                  xml.ReturnAddress2 origin.address2 if origin.address2.present?
                  xml.ReturnAddress3 origin.address3 if origin.address3.present?
                  xml.FromCity origin.city if origin.city.present?
                  xml.FromState origin.state if origin.state.present?
                  xml.FromPostalCode origin.zip if origin.zip.present?
                  xml.FromPhone origin.phone.gsub(/[(\- )]/, '') if origin.phone.present?

                  xml.ToName destination.name if destination.name.present?
                  xml.ToCompany destination.company_name if destination.company_name.present?
                  xml.ToAddress1 destination.address1 if destination.address1.present?
                  xml.ToAddress2 destination.address2 if destination.address2.present?
                  xml.ToAddress3 destination.address3 if destination.address3.present?
                  xml.ToCity destination.city if destination.city.present?
                  xml.ToState destination.state if destination.state.present?
                  xml.ToPostalCode destination.zip if destination.zip.present?
                  xml.ToCountryCode destination.country_code if destination.country_code.present?
                  xml.ToPhone destination.phone.gsub(/[(\- )]/, '') if destination.phone.present?
                }
              }
            }
          }
        end
        builder.to_xml
      end

      def parse_get_postage_label_response(response, options = {})
        xml = Nokogiri::XML(response)
        xml.remove_namespaces!
        response_hash = {}
        response_hash[:response_code] = xml.xpath('//Status').text
        if successful_response?(xml)
          response_hash[:success] = true
          if options[:label_subtype].present?
            label = ""
            xml.xpath("//Image").each do |image|
              label << image
            end
            response_hash[:label] = label
          else
            response_hash[:label] = xml.xpath('//Base64LabelImage').text
          end
          response_hash[:shipment_id] = xml.xpath('//TrackingNumber').text
          response_hash[:charges] = xml.xpath('//FinalPostage').text
        else
          response_hash[:error_description] = xml.xpath("//ErrorMessage").text
        end
        response_hash
      end


      def build_get_refund_request(shipment_id, options = {})
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.send("soap:Envelope", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
                                    "xmlns:xsd" => "http://www.w3.org/2001/XMLSchema",
                                    "xmlns:soap" => "http://schemas.xmlsoap.org/soap/envelope/") {
            xml.send("soap:Body") {
              xml.GetRefund(xmlns: "www.envmgr.com/LabelService") {
                xml.RefundRequest {
                  xml.RequesterID options[:test] ? 'lxxx' : options[:requester_id]
                  xml.RequestID "1" #Change this sometime later maybe...
                  xml.CertifiedIntermediary {
                    if options[:token].present?
                      xml.Token options[:token]
                    else
                      xml.AccountID options[:account_id]
                      xml.PassPhrase options[:old_phrase]
                    end

                  }
                  xml.PicNumbers {
                    xml.PicNumber shipment_id
                  }
                }
              }
            }
          }
        end
        builder.to_xml
      end

      def parse_get_refund_response(response)
        xml = Nokogiri::XML(response)
        xml.remove_namespaces!
        response_hash = {}
        if xml.xpath('//RefundStatus').text == "Approved"
          response_hash[:success] = true
        else
          response_hash[:error_code] = xml.xpath('//RefundStatus').text
          response_hash[:error_description] = xml.xpath("//RefundStatusMessage").text
        end
        response_hash
      end

  end
end
