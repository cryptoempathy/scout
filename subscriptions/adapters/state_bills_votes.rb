module Subscriptions
  module Adapters

    class StateBillsVotes
      ITEM_TYPE = 'state_bill'
      ITEM_ADAPTER = true

      def self.url_for(subscription, function, options = {})
        endpoint = "http://openstates.org/api/v1"
        api_key = options[:api_key] || Environment.config['subscriptions']['sunlight_api_key']

        fields = %w{ id bill_id state chamber session votes }

        item_id = subscription.interest_in

        # item_id is of the form ":state/:session/:chamber/:bill_id" (URI encoded already)
        url = "#{endpoint}/bills/#{URI.encode item_id.gsub('__', '/').gsub('_', ' ')}/?apikey=#{api_key}"
        url << "&fields=#{fields.join ','}"

        url
      end

      def self.search_name(subscription)
        "Votes"
      end

      def self.item_name(subscription)
        "Vote"
      end

      def self.short_name(number, interest)
        number == 1 ? 'vote' : 'votes'
      end

      def self.direct_item_url(vote, interest)
        "http://openstates.org/#{vote['state']}/votes/#{vote['id']}"
      end

      def self.items_for(response, function, options = {})
        return nil unless response['votes']

        votes = []
        response['votes'].each do |vote|
          votes << item_for(response['id'], vote)
        end
        votes
      end


      # private

      def self.item_for(bill_id, vote)
        return nil unless vote

        vote['date'] = Time.zone.parse vote['date']

        SeenItem.new(
          item_id: "#{bill_id}-vote-#{vote['date'].to_i}",
          date: vote['date'],
          data: vote
        )
      end

    end

  end
end