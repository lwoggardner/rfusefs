require 'fusefs'

describe "Using fusefs compatibility mode" do
	describe FuseFS do
		
		it "should indicate FuseFS compatibility" do
      expect(FuseFS::RFUSEFS_COMPATIBILITY).to eq(false)
		end
		
		it "should use FuseFS compatible raw calls" 
	end
end
