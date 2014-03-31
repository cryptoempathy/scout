require './test/test_helper'

class RemoteTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include TestHelper::Methods
  include FactoryGirl::Syntax::Methods


  def test_service_sync_new_interests
    service = "service1"
    key = Environment.services["service1"]['secret_key']
    email = "test@example.com"
    notifications = "email_daily"

    # user not created yet
    assert_nil User.where(email: email).first
    count = User.count
    interest_count = Interest.count

    # new item subscription
    item_id = "hr4192-112"
    item_type = "bill"
    mock_item item_id, item_type

    interest1 = {
      'active' => true,
      'changed_at' => Time.now,

      'interest_type' => "item",
      'item_type' => item_type,
      'item_id' => item_id
    }

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: key,
      notifications: notifications,
      interests: [interest1]
    }.to_json
    assert_response 201

    assert_equal 1, json_response['actions']['added']
    assert_equal 0, json_response['actions']['removed']

    user = User.where(email: email).first
    assert_not_nil user
    assert_equal count + 1, User.count
    assert_equal interest_count + 1, Interest.count

    assert_equal notifications, user.notifications
    assert user.confirmed?
    assert_not_nil user.password_hash
    assert !user.should_change_password?
    assert !user.announcements?
    assert !user.organization_announcements?

    assert_not_nil user.synced_at

    assert_equal 1, user.interests.count
    assert_equal item_id, user.interests.first.in

    # new item subscription for existing user
    item_id = "hr4193-112"
    item_type = "bill"
    mock_item item_id, item_type

    # add this item on, keep old item, should be idempotent
    interest2 = {
      'active' => true,
      'changed_at' => Time.now.to_i, # test out using a posix time

      'interest_type' => "item",
      'item_type' => item_type,
      'item_id' => item_id
    }


    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: key,
      notifications: notifications,
      interests: [interest1, interest2]
    }.to_json
    assert_response 201

    assert_equal 1, json_response['actions']['added']
    assert_equal 0, json_response['actions']['removed']

    user.reload

    assert_equal count + 1, User.count
    assert_equal interest_count + 2, Interest.count

    assert_equal 2, user.interests.count
    assert_equal item_id, user.interests.last.in

    # pretend an hour has passed
    user.interests.each do |interest|
      interest.update_attribute :updated_at, 1.hour.ago
    end

    # now tear it down
    interest2['active'] = false

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: key,
      notifications: notifications,
      interests: [interest2]
    }.to_json
    assert_response 201

    assert_equal 0, json_response['actions']['added']
    assert_equal 1, json_response['actions']['removed']

    user.reload

    assert_equal count + 1, User.count
    assert_equal interest_count + 1, Interest.count

    assert_equal 1, user.interests.count
    assert_equal interest1['item_id'], user.interests.last.in


    # tear the first down, add the second one back
    interest1['active'] = false
    interest2['active'] = true
    mock_item interest2['item_id'], interest2['item_type']

    # add in a search interest
    interest3 = {
      'active' => true,
      'changed_at' => Time.now,

      'interest_type' => 'search',
      'search_type' => 'state_bills',
      'in' => 'health',
      'query_type' => 'advanced',
      'filters' => {'state' => 'DE'}
    }


    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: key,
      notifications: notifications,
      interests: [interest1, interest2, interest3]
    }.to_json
    assert_response 201

    assert_equal 2, json_response['actions']['added']
    assert_equal 1, json_response['actions']['removed']

    user.reload

    assert_equal count + 1, User.count
    assert_equal interest_count + 2, Interest.count

    assert_equal 2, user.interests.count
    assert_equal interest2['item_id'], user.interests.first.in

    search_interest = user.interests.last
    assert_equal interest3['in'], search_interest.in
    assert_equal 'DE', search_interest.data['state']
  end

  # covers a real bug where Swot was mutating emails in-place,
  # and de-duping was not happening correctly
  def test_service_does_not_lowercase
    service = "service1"
    key = Environment.services["service1"]['secret_key']
    notifications = "email_daily"

    email = "Test@example.com" # capitalized!

    # user exists, 1 user, 0 alerts
    assert_nil User.where(email: email).first
    count = User.count
    interest_count = Interest.count

    # new item subscription
    item_id = "hr4192-112"
    item_type = "bill"
    mock_item item_id, item_type

    interest1 = {
      'active' => true,
      'changed_at' => Time.now,

      'interest_type' => "item",
      'item_type' => item_type,
      'item_id' => item_id
    }

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: key,
      notifications: notifications,
      interests: [interest1]
    }.to_json
    assert_response 201

    assert_equal 1, json_response['actions']['added']
    assert_equal 0, json_response['actions']['removed']

    # user created under given email
    assert_not_nil User.where(email: email).first
    assert_nil User.where(email: email.downcase).first

    assert_equal count + 1, User.count
    assert_equal interest_count + 1, Interest.count
  end


  # no key, bunk key, valid key for wrong service
  def test_service_sync_invalid_secret_key
    service = "service1"
    key = Environment.services["service2"]['secret_key']
    email = "test@example.com"

    user = create :service_user, email: email

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: key
    }.to_json

    assert_response 403
    assert_match /not a supported service/i, last_response.body
  end

  def test_service_sync_invalid_json
    service = Environment.services.keys.first
    email = "test@example.com"
    user = create :service_user, email: email

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: Environment.services[service]['secret_key']
    }
    assert_response 500
    assert_match /parsing json/i, last_response.body
  end

  # user account exists, but has different service
  def test_service_sync_service_for_native_user
    # a native Scout user
    email = "test@example.com"
    user = create :user, email: email

    # one existing item subscription, native to Scout
    item_id = "hr4192-112"
    item_type = "bill"
    mock_item item_id, item_type

    interest1 = Interest.for_item user, item_id, item_type
    interest1.save!

    count = User.count
    assert_equal 1, user.interests.count


    # now this user joins a remote service, and makes an interest there

    service = Environment.services.keys.first
    notifications = "email_daily"

    item_id = "hr4193-112"
    item_type = "bill"
    mock_item item_id, item_type

    interest2 = {
      'active' => true,
      'changed_at' => Time.now,

      'interest_type' => "item",
      'item_type' => item_type,
      'item_id' => item_id
    }

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: Environment.services[service]['secret_key'],
      notifications: notifications,
      interests: [interest2]
    }.to_json

    assert_response 201

    assert_equal 1, json_response['actions']['added']
    assert_equal 0, json_response['actions']['removed']

    user = User.where(email: email).first

    assert_not_nil user
    assert_equal count, User.count
    assert_equal 2, user.interests.count

    created = user.interests.asc(:_id).last
    assert_equal created.in, item_id
    assert_equal created.item_type, item_type

    # now turn the user's email notifications off

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: Environment.services[service]['secret_key'],
      notifications: "none",
      interests: []
    }.to_json

    assert_response 201

    assert_equal 0, json_response['actions']['added']
    assert_equal 0, json_response['actions']['removed']

    user = User.where(email: email).first
    assert_equal 2, user.interests.count
    assert_equal "none", user.notifications


    # pretend an hour has passed

    user.interests.each do |interest|
      interest.update_attribute :updated_at, 1.hour.ago
    end


    # now remove the first interest

    remove_interest2 = {
      'active' => false,
      'changed_at' => Time.now,

      'interest_type' => "item",
      'item_type' => item_type,
      'item_id' => item_id
    }

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: Environment.services[service]['secret_key'],
      notifications: notifications,
      interests: [remove_interest2]
    }.to_json

    assert_response 201

    assert_equal 0, json_response['actions']['added']
    assert_equal 1, json_response['actions']['removed']

    user = User.where(email: email).first
    assert_equal 1, user.interests.count
    assert_equal interest1.in, user.interests.first.in
    assert_equal notifications, user.notifications # changed back


    # now, remove the *original* native interest, through the sync endpoint
    # this is going to be possible for now.

    remove_interest1 = {
      'active' => false,
      'changed_at' => Time.now,

      'interest_type' => "item",
      'item_type' => interest1.item_type,
      'item_id' => interest1.in
    }

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: Environment.services[service]['secret_key'],
      notifications: notifications,
      interests: [remove_interest1]
    }.to_json

    assert_response 201

    assert_equal 0, json_response['actions']['added']
    assert_equal 1, json_response['actions']['removed']

    user = User.where(email: email).first
    assert_equal 0, user.interests.count
  end

  # bad email, let's say
  def test_service_sync_invalid_user
    service = "service1"
    key = Environment.services["service1"]['secret_key']
    email = "invalid.email"
    notifications = "email_daily"

    # user not created yet
    assert_nil User.where(email: email).first
    count = User.count

    # new item subscription
    item_id = "hr4192-112"
    item_type = "bill"
    mock_item item_id, item_type

    interest1 = {
      'active' => true,
      'changed_at' => Time.now,

      'interest_type' => "item",
      'item_type' => item_type,
      'item_id' => item_id
    }

    post "/remote/service/sync", {
      email: email,
      service: service,
      secret_key: key,
      notifications: notifications,
      interests: [interest1]
    }.to_json

    assert_response 403
    assert_match /invalid new user/i, last_response.body

    assert_equal count, User.count
    assert_nil User.where(email: email).first
  end

  def test_subscribe_by_sms
    phone = "+15555551212"
    item_id = "hr4192-112"
    item_type = "bill"

    mock_item item_id, item_type

    assert_nil User.where(phone: phone).first
    interest_count = Interest.count
    subscriptions_count = Subscription.count

    # verify SMS was sent to the user telling them to confirm
    SMS.should_receive(:deliver!).with("Remote Subscription", phone, anything)

    post "/remote/subscribe/sms", {
      phone: phone, interest_type: "item", item_id: item_id, item_type: item_type,
      source: "testing"
    }
    assert_response 200

    user = User.where(:phone => phone).first
    assert_not_nil user

    assert !user.confirmed?
    assert_equal "none", user.notifications

    assert_not_nil user.password_hash
    assert user.should_change_password
    assert_equal "testing", user.source

    assert_equal phone, user.phone
    assert !user.phone_confirmed?

    assert !user.announcements
    assert !user.organization_announcements

    assert_equal 1, user.interests.count
    interest = user.interests.first

    assert_equal "item", interest.interest_type
    assert_equal item_type, interest.item_type
    assert_equal item_id, interest.in
    assert_equal "sms", interest.notifications
    assert_not_nil interest.data['bill_id'] # loaded from fixture
  end

  def test_subscribe_by_sms_with_taken_phone_number_creates_new_interest_but_not_new_account
    # use an intentionally non-standard phone number, to make sure the matching works
    phone = "5555551212"
    item_id = "hr4192-112"
    item_type = "bill"

    user = create :user, :phone => phone # confirmation doesn't matter
    assert user.confirmed?

    mock_item item_id, item_type

    count = User.count
    assert_equal 0, user.interests.count

    # SMS should not be sent
    Admin.should_not_receive(:new_user)
    SMS.should_not_receive(:deliver!).with("Remote Subscription", phone, anything)

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "item", :item_id => item_id, :item_type => item_type,
      :source => "testing"
    }
    assert_response 200

    user.reload
    assert_equal count, User.count
    assert_equal 1, user.interests.count
    assert user.confirmed? # still got it

    interest = user.interests.first

    assert_equal "item", interest.interest_type
    assert_equal item_type, interest.item_type
    assert_equal item_id, interest.in
    assert_equal "sms", interest.notifications
    assert_not_nil interest.data['bill_id'] # loaded from fixture

    # verify *no* SMS was sent to user, not needed
    #TODO
  end

  def test_subscribe_by_sms_with_blank_phone_number_fails
    phone = ""
    item_id = "hr4192-112"
    item_type = "bill"

    mock_item item_id, item_type

    assert_nil User.where(:phone => phone).first
    interest_count = Interest.count
    subscriptions_count = Subscription.count

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "item", :item_id => item_id, :item_type => item_type,
      :source => "testing"
    }
    assert_response 500
    assert_nil User.where(:phone => phone).first
  end

  def test_subscribe_by_sms_with_invalid_interest_details_fails
    # test on 'interest_type', 'item_type', 'item_id'
    phone = "+15555551212"
    item_id = "hr4192-112"
    item_type = "bill"

    assert_nil User.where(:phone => phone).first
    interest_count = Interest.count
    subscriptions_count = Subscription.count

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "item", :item_id => "", :item_type => item_type,
      :source => "testing"
    }
    assert_response 500
    assert_nil User.where(:phone => phone).first

    post "/remote/subscribe/sms", {
      :phone => phone, :interest_type => "", :item_id => item_id, :item_type => item_type,
      :source => "testing"
    }
    assert_response 500
    assert_nil User.where(:phone => phone).first


    # relaxed until COC team can update their end

    # post "/remote/subscribe/sms", {
    #   :phone => phone, :interest_type => "item", :item_id => item_id, :item_type => "",
    #   :source => "testing"
    # }
    # assert_response 500
    # assert_nil User.where(:phone => phone).first
  end

  def test_subscribe_by_sms_when_remote_item_doesnt_exist_fails
    phone = "+15555551212"
    item_id = "hr4195-112" # no fixture for this
    item_type = "bill"

    mock_item item_id, item_type # should mock it to return nil

    assert_nil User.where(phone: phone).first
    interest_count = Interest.count
    subscriptions_count = Subscription.count

    post "/remote/subscribe/sms", {
      phone: phone, interest_type: "item", item_id: item_id, item_type: item_type,
      source: "testing"
    }
    assert_response 500

    assert_nil User.where(phone: phone).first
  end


  def test_receive_confirm
    phone = "+15555551212"
    user = create :phone_user

    assert !user.confirmed?
    assert !user.phone_confirmed?
    current_pass = user.password_hash
    assert user.should_change_password

    post "/remote/twilio/receive", {
      "Body" => "c",
      "From" => phone
    }
    assert_response 200

    user.reload
    assert user.confirmed?
    assert user.phone_confirmed?
    assert_not_equal current_pass, user.password_hash
    assert user.should_change_password
    # SMS should also have been sent with the user's password
  end

  def test_receive_confirm_with_no_phone_or_body
    phone = "+15555551212"
    user = create :phone_user

    assert !user.confirmed?
    assert !user.phone_confirmed?
    current_pass = user.password_hash
    assert user.should_change_password

    post "/remote/twilio/receive", {
      "Body" => "c",
      "From" => ""
    }
    assert_response 500

    user.reload
    assert !user.confirmed?
    assert !user.phone_confirmed?

    post "/remote/twilio/receive", {
      "Body" => "",
      "From" => phone
    }
    assert_response 500

    user.reload
    assert !user.confirmed?
    assert !user.phone_confirmed?
  end

  def test_receive_confirm_from_unknown_phone
    phone = "+15555551212"
    user = create :phone_user, :phone => phone.succ

    assert_nil User.by_phone(phone)

    assert !user.confirmed?
    assert !user.phone_confirmed?
    current_pass = user.password_hash
    assert user.should_change_password

    post "/remote/twilio/receive", {
      "Body" => "c",
      "From" => phone
    }
    assert_response 404

    user.reload
    assert !user.confirmed?
    assert !user.phone_confirmed?
  end

  def test_receive_confirm_from_phone_that_has_existing_confirmed_account
    phone = "+15555551212"
    user = create :user, :phone => phone, :phone_confirmed => true

    assert user.phone_confirmed?
    assert user.confirmed?
    current_pass = user.password_hash
    assert !user.should_change_password

    post "/remote/twilio/receive", {
      "Body" => "c",
      "From" => phone
    }
    assert_response 200

    user.reload
    assert user.confirmed?
    assert user.phone_confirmed?
    assert_equal current_pass, user.password_hash
    assert !user.should_change_password
  end


end