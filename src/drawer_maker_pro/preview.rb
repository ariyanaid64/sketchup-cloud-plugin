require_relative 'cabinet_calculator'

module SketchupCloud
  module DrawerMakerPro
    # Dialog preview data, shared by the SketchUp dialog and the browser test.
    module Preview
      module_function

      def payload(kind, space, params, request_id = nil)
        if kind == 'cabinet'
          plan = CabinetCalculator.compute(space, params)
          fixed = plan[:parts]
          moving = (plan[:doors] + plan[:drawers]).flat_map { |item| item[:parts] }
          count = plan[:doors].length + plan[:drawers].length
        else
          plan = Calculator.compute(space, params)
          fixed = plan.flat_map { |drawer| drawer[:fixed] || [] }
          moving = plan.flat_map { |drawer| drawer[:parts] }
          count = plan.length
        end
        parts = fixed.map(&:to_h) + moving.map { |part| part.to_h.merge(moving: true) }
        { parts: parts, count: count, requestId: request_id }
      end
    end
  end
end
