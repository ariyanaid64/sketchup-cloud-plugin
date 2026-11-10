require 'json'
require_relative '../src/drawer_maker_pro/preview'

request = JSON.parse($stdin.read)
if request['normalize']
  calculator = if request['kind'] == 'cabinet'
                 SketchupCloud::DrawerMakerPro::CabinetCalculator
               else
                 SketchupCloud::DrawerMakerPro::Calculator
               end
  puts JSON.generate(calculator.normalize(request.fetch('params', {})))
else
  begin
    puts JSON.generate(SketchupCloud::DrawerMakerPro::Preview.payload(request['kind'], request.fetch('space'),
                                                                     request.fetch('params'), request['requestId']))
  rescue ArgumentError => e
    puts JSON.generate(error: e.message, requestId: request['requestId'])
  end
end
