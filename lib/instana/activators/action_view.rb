module Instana
  module Activators
    class ActionView < Activator
      def can_instrument?
        defined?(::ActionView::PartialRenderer)
      end

      def instrument
        require 'instana/instrumentation/action_view'

        ::ActionView::PartialRenderer
          .prepend(Instana::Instrumentation::ActionView)

        true
      end
    end
  end
end
