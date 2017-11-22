class User < ActiveRecord::Base
	has_many :cards
    has_secure_password
    serialize :orders
end
