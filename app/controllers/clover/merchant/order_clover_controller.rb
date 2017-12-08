
require "http"
require 'json'

class Clover::Merchant::OrderCloverController < ApplicationController
# get merchants


    def initialize
        @clover_base_url         = Rails.application.secrets.clover_base_url
        @clover_base_api_url     = Rails.application.secrets.clover_base_api_url
    end

    # 1.create an order
    def new

        shop = get_shop(params[:id])
        shop_id         = shop.remote_id
        access_token    = shop.token

        order = params["order"]

        is_drive_through = params["isDriveThrough"]

        # 1.create an order
        begin
            puts "Creating new order for shop_id: #{shop_id}"
            new_order_request = HTTP
            .headers(
                :authorization => "Bearer #{access_token}",
                :content_type => "application/json",
            )
            .post(
                "#{@clover_base_api_url}/v3/merchants/#{shop_id}/orders",
                :json => {
                    "state":    "open",
                    "note":     "MOB APP #{"| DRIVE THROUGH" if is_drive_through}",
                    "title":    "Thanks for the remote order!"
                }
            )
            order_resp = new_order_request.parse
            order_id = order_resp["id"]
        rescue HTTP::ResponseError => e
            raise "Error on new order: #{e.message}"

            render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
            return
        end

        # 1.1 if auth -> add that to user
        if params[:auth] != nil && user = get_user(params[:auth]["token"])
            user.orders << "#{shop_id}|#{order_id}"
            user.save
            # 1.2 if remote auth -> add that to order
        end

        remote_user = user.remote_id if user !=nil

        modifierIdsPerItem = order.reduce({}) do |acc, item|
            selected_mods = item["selectedModifiers"] || []
            acc[item["uuid"]] = selected_mods.map {|mod| mod["selectedModifier"]["id"]}
            acc
        end

        # 2. update that shit with bulk items
        begin
            puts "Setting line items for shop_id: #{shop_id}"
            new_order_lineitems_request = HTTP
            .headers(
                :authorization => "Bearer #{access_token}",
                :content_type => "application/json",
            )
            .post(
                "#{@clover_base_api_url}/v3/merchants/#{shop_id}/orders/#{order_id}/bulk_line_items",
                :json => {
                    "items": order.map do |item|
                        item[:alternateName] = item["uuid"] #!!!
                        item[:note] = "through mob app"
                        item[:userDate] = "for #{user.email}" if user != nil
                        item
                    end
                }
            )
            lineitems_resp = new_order_lineitems_request.parse
        rescue HTTP::ResponseError => e
            raise "Error on new lineitems order: #{e.message}"

            render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
            return
        end

        # 3. update EVERY item with modifiers
        lineitems_resp.each do |lineitem|
            lineitem_id = lineitem["id"]
            modifiers_to_add = modifierIdsPerItem[lineitem["alternateName"]] || []
            # 3.1 ADD EVERY FUCKING MOD SEPARATELY TO EVERY FREAKING ITEM???
            modifiers_to_add.each do |modId|
                begin
                    puts "Setting modifier #{modId} for lineitem: #{lineitem_id}"
                    new_mod_lineitems_request = HTTP
                    .headers(
                        :authorization => "Bearer #{access_token}",
                        :content_type => "application/json",
                    )
                    .post(
                        "#{@clover_base_api_url}/v3/merchants/#{shop_id}/orders/#{order_id}/line_items/#{lineitem_id}/modifications",
                        :json => {
                            "modifier": {
                                "id": modId
                            }
                        }
                    )
                    modifier_resp = new_mod_lineitems_request.parse
                rescue HTTP::ResponseError => e
                    raise "Error on new modId for lineitem: #{e.message}"

                    render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
                    return
                end
            end
        end

        total_cost = 0
        total_tax = 0

        # 5. CALCULATE TOTAL AND UPDATE THAT FUCK

        order.each do |item|
            total_cost = total_cost + item["priceCalculated"];
            item_tax_rate = item["taxRates"]["elements"] || []
            item_tax_perc = item_tax_rate.reduce(0) {|acc, tax_rate| (acc +  (tax_rate["rate"].to_f)/100000)}
            total_tax += item["priceCalculated"] * item_tax_perc/100
        end

        begin
            puts "Updating order #{order_id} with total: #{total_cost+total_tax}"
            new_order_lineitems_request = HTTP
            .headers(
                :authorization => "Bearer #{access_token}",
                :content_type => "application/json",
            )
            .post(
                "#{@clover_base_api_url}/v3/merchants/#{shop_id}/orders/#{order_id}",
                :json => {
                    "total": (total_cost + total_tax)
                }
            )
            lineitems_resp = new_order_lineitems_request.parse
        rescue HTTP::ResponseError => e
            raise "Error on new updateing order with cost: #{e.message}"

            render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
            return
        end

        # 6. get that shit and send results back
        # optionally -> get and send the receipt
        remote_order = get_remote_order(access_token, shop_id, order_id)
        render json: {:status => 200, :data => {order: remote_order}}
    end

    def get_receipt
        order_id = params[:order_id]

        begin
            puts "Getting receipt for #{order_id}"
            new_order_lineitems_request = HTTP
            .get(
                "#{@clover_base_api_url}/r/#{order_id}"
            )
        rescue HTTP::ResponseError => e
            raise "Error on getting receipt: #{e.message}"

            render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
            return
        end

        stringed = new_order_lineitems_request.to_s

        stringed.gsub! 'href="/assets', "href=\"#{@clover_base_api_url}/assets"
        stringed.gsub! 'src="/assets', "src=\"#{@clover_base_api_url}/assets"

        stringed.gsub! /<script[\s\S]*?>[\s\S]*?<\/script>/, ''

        render :text => stringed
    end

    # 2.update it with items
    def update
    end

    # 3.delete
    def delete
    end

    def get_remote_order(access_token, shop_id, order_id)
        begin
            puts "Getting order #{order_id}"
            new_order_lineitems_request = HTTP
            .headers(
                :authorization => "Bearer #{access_token}"
            )
            .get(
                "#{@clover_base_api_url}/v3/merchants/#{shop_id}/orders/#{order_id}?expand=lineItems.modifications,lineItems.taxRates"
            )

            new_order_lineitems_request.parse
        rescue HTTP::ResponseError => e
            raise "Error on getting order: #{e.message}"

            render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
            return
        end
    end

    def get_user_orders
        user = get_user(params[:token])

        shopsDic = {}
        orders = []

        user.orders.each do |orderSet|
            orderSetArr = orderSet.split("|")
            shop_id     = orderSetArr.first

            if shop = shopsDic[shop_id.to_sym]
            else shop = get_shop(shop_id)
            end

            shopsDic[shop_id.to_sym] = shop

            order_id    = orderSetArr.last

            begin
                puts "Getting order #{order_id} of shop: #{shop_id}"
                order_req = HTTP
                .headers(
                    :authorization => "Bearer #{shop["token"]}"
                )
                .get(
                    "#{@clover_base_api_url}/v3/merchants/#{shop_id}/orders/#{order_id}?expand=lineItems.modifications,lineItems.taxRates"
                )
                order_resp = order_req.parse
                orders << order_resp
            rescue HTTP::ResponseError => e
                raise "Error on new modId for lineitem: #{e.message}"

                render :json => {:error => JSON.parse(e.response_body)["errors"]}, :status => 400
                return
            end
        end

        render json: {:status => 200, :data => {orders: orders}}
    end

	def get_user(user_auth_token)
		User.find_by_auth_token(user_auth_token) or not_found
	end

    def get_shop(remote_id)
        Shop.find_by_remote_id(remote_id) or not_found
    end

    def not_found
        raise ActionController::RoutingError.new('Not Found')
    end

end
# get categories
# get merchant
# get oppening hours
# get devices
# get items
# get modifiers
# creat and order
# update order
# cancell order/refund