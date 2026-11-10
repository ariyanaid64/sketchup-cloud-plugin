require 'json'
require_relative '../src/drawer_maker_pro/calculator'
require_relative '../src/drawer_maker_pro/cabinet_calculator'

request = JSON.parse($stdin.read)
calculator = request['kind'] == 'cabinet' ? SketchupCloud::DrawerMakerPro::CabinetCalculator : SketchupCloud::DrawerMakerPro::Calculator
if request['normalize']
  puts JSON.generate(calculator.normalize(request.fetch('params', {})))
else
  begin
    plan = calculator.compute(request.fetch('space'), request.fetch('params'))
    if request['kind'] == 'cabinet'
      parts = plan[:parts] + plan[:doors].flat_map { |door| door[:parts] }
      count = plan[:openings].length
    else
      parts = plan.flat_map { |drawer| drawer[:parts] }
      count = plan.length
    end
    puts JSON.generate(parts: parts.map(&:to_h), count: count, requestId: request['requestId'])
  rescue ArgumentError => e
    puts JSON.generate(error: e.message, requestId: request['requestId'])
  end
end
