module Subscriptions
  module Adapters

    class FederalBillsUpcomingFloor
      ITEM_TYPE = 'bill'
      ITEM_ADAPTER = true

      def self.url_for(subscription, function, options = {})
        api_key = options[:api_key] || Environment.config['subscriptions']['sunlight_api_key']

        if Environment.config['subscriptions']['congress_endpoint'].present?
          endpoint = Environment.config['subscriptions']['congress_endpoint'].dup
        else
          endpoint = "https://congress.api.sunlightfoundation.com"
        end

        fields = %w{ source_type bill_id chamber url legislative_day range }

        bill_id = subscription.interest_in

        url = "#{endpoint}/upcoming_bills?apikey=#{api_key}"
        url << "&bill_id=#{bill_id}"
        url << "&fields=#{fields.join ','}"

        url
      end

      def self.search_name(subscription)
        "On the Floor"
      end

      def self.item_name(subscription)
        "Scheduled debate"
      end

      def self.short_name(number, interest)
        number == 1 ? 'floor notice' : 'floor notices'
      end

      def self.direct_item_url(upcoming, interest)
        upcoming['url']
      end

      # takes parsed response and returns an array where each item is
      # a hash containing the id, title, and post date of each item found
      def self.items_for(response, function, options = {})
        return nil unless response['results']

        response['results'].map do |upcoming|
          item_for upcoming
        end
      end


      def self.item_for(upcoming)
        return nil unless upcoming

        SeenItem.new(
          item_id: "#{upcoming['legislative_day']}-#{upcoming['chamber']}",
          date: upcoming['legislative_day'],
          data: upcoming
        )
      end

    end

  end
end