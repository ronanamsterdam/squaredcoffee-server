require 'aws-sdk-ses'

class ApplicationMailer < ActionMailer::Base
    default from: "from@example.com"
    layout 'mailer'

    def make_email_sub_payload(data, charset)
        binding.pry
        default_charset = 'UTF-8'
        {
            data: data,
            charset: charset || defaultCharset,
        }
    end

    def make_email_payload(params)
        binding.pry
        body = {}
        to_addresses = params[:receiver].is_a?(Array) ? params[:receiver] : [params[:receiver]]

        if params[:body_html] != nil
            body.html = make_email_sub_payload(params[:body_html])
        end
        binding.pry
        if params[:body_text]
            body.text = make_email_sub_payload(params[:body_text])
        end
        binding.pry
        return {
            destination: {
                to_addresses: Rails.application.secrets["emails"]["master_override"] && [Rails.application.secrets["emails"]["master_override"]] || to_addresses,
            },
            message: {
                body:       body,
                subject:    make_email_sub_payload(params[:subject]),
            },
            source: params[:sender] || Rails.application.secrets["aws"]["ses"]["sender"],
        }
    end

    def send_email(params)
        binding.pry
        ses = Aws::SES::Client.new({
            region: Rails.application.secrets["aws"]["ses"]["region"],
        })
        binding.pry
        payload = make_email_payload(params)
        binding.pry
        res = ses.send_email(payload)
        binding.pry
    end
end
