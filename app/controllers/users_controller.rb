class UsersController < ApplicationController
	protect_from_forgery with: :null_session

	def initialize
		@access_token = Rails.application.secrets.square_access_token

		SquareConnect.configure do |config|
			# Configure OAuth2 access token for authorization: oauth2
			config.access_token = @access_token
		end
	end

	def new_remote
		customer_api = SquareConnect::CustomersApi.new
		reference_id = SecureRandom.uuid

        if session[:user_id] == nil
            session[:user_id] = User.find_by_auth_token(params[:token]).id
        end

		customer_request = {
			given_name: params[:billing][:given_name],
			family_name: params[:billing][:family_name],
			email_address: params[:billing][:email_address],
			address: {
				address_line_1: params[:billing][:address_line_1],
				address_line_2: params[:billing][:address_line_2],
				locality: params[:billing][:locality],
				administrative_district_level_1: params[:billing][:administrative_district_level_1],
				postal_code: params[:billing][:postal_code],
				country: params[:billing][:country]
			},
			phone_number: params[:billing][:phone_number],
			reference_id: reference_id,
		}

		begin
			customer_response = customer_api.create_customer(customer_request)
			puts 'Customer ID to use with CreateCustomerCard:'
			puts customer_response
		rescue SquareConnect::ApiError => e
            raise "Error encountered while creating customer: #{e.message}"

            render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
			return
		end

		customer_res = customer_response.customer


		user = User.update(
            session[:user_id],
			# TODO: token class
			remote_id: customer_res.id
		)

		if user.save
			session[:user_id] = user.id

            render json: {:status => 200, :data => {
                token: user.auth_token,
                remoteAuthorized: true
            }}
		else
            render :json => {:error => '[user|new_remote]: too bad'}, :status => 500
		end
	end

	def new
		puts params
		user = User.new({
			email: params[:email],
			password: params[:password],
			password_confirmation: params[:password_confirmation],
			auth_token: SecureRandom.uuid
		})
		if user.save
			session[:user_id] = user.id
			render json: {:status => 200, :data => {token: user.auth_token}}
		else
			render :json => {:error => '[user|new]: too bad'}, :status => 500
		end
    end

	def get_user(user_auth_token)
		# TODO: do Token model
		# exps and created fields
		@user ||= User.find(session[:user_id]) if session[:user_id] else User.find_by_auth_token(user_auth_token)
	end

    def update
        # todo
    end

    def delete
        # todo
    end

    def get_account_info
        user = get_user(params[:token])
        user_remote = get_remote_user(user.remote_id).customer

        puts user
        puts user_remote

        render json: {:status => 200, :data => {
            billing:        {
                given_name:     user_remote.given_name,
                family_name:    user_remote.family_name,
                email_address:  user_remote.email_address,
                address:        user_remote.address,
                phone_number:   user_remote.phone_number,
            },
            userAccount: {
                email:      user.email
            }
        }}
    end

    def get_remote_user(remote_id)
        begin
            api = SquareConnect::CustomersApi.new
            return api.retrieve_customer(remote_id)
        rescue SquareConnect::ApiError => e
            raise "Error encountered while retreaving customer: #{e.message}"

            render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
            return false
        end
    end

    def update_remote
        user = get_user(params[:token])

        puts user
        api = SquareConnect::CustomersApi.new

        customer_request = {
            given_name: params[:billing][:given_name],
            family_name: params[:billing][:family_name],
            email_address: params[:billing][:email_address],
            address: {
                address_line_1: params[:billing][:address_line_1],
                address_line_2: params[:billing][:address_line_2],
                locality: params[:billing][:locality],
                administrative_district_level_1: params[:billing][:administrative_district_level_1],
                postal_code: params[:billing][:postal_code],
                country: params[:billing][:country]
            },
            phone_number: params[:billing][:phone_number],
        }

        begin
            puts params[:billing][:postal_code]
            customer_res = api.update_customer(user.remote_id, customer_request)
        rescue SquareConnect::ApiError => e
            raise "Error encountered while updating customer: #{e.message}"

            render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
            return false
        end

        puts customer_res

        render json: {:status => 200}
    end
end
