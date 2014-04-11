# A statement acknowledging the successful sending of a notification to a
# subscriber. The notification may be, for example, an email message about new
# items related to an interest of the subscriber.
class Receipt
  include Mongoid::Document
  include Mongoid::Timestamps

  # @return [Array<Hash>] a list of the attributes of the deliveries made in
  #   this transaction (each delivery is about a single item).
  #   these deliveries will have had their `item.data` fields removed, to save storage.
  field :deliveries, :type => Array

  # @return [String] the user's ID
  field :user_id
  # @return [String] the user's email address, if delivered via email
  field :user_email
  # @return [String] the service that generated the user, if not Scout itself,
  #   e.g. "open_states"
  field :user_service

  # @return [String] "email"
  # TODO: kill this
  field :mechanism

  # @return [String] the email's "Subject" header
  field :subject
  # @return [Time] the time at which the notification was sent
  field :delivered_at, :type => Time

  index delivered_at: 1
  index user_id: 1
  index user_email: 1
  index user_service: 1
  index({created_at: 1, user_service: 1})
  index mechanism: 1
  index created_at: 1
  index({mechanism: 1, user_service: 1, created_at: 1})

  validates_presence_of :delivered_at

  # if the user is still around, no harm if it's not
  belongs_to :user

  scope :for_time, ->(start, ending) {
    where(delivered_at: {
      "$gt" => Time.zone.parse(start).midnight,
      "$lt" => Time.zone.parse(ending).midnight
    })
  }
end
