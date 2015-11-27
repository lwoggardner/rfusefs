require 'fusefs'

describe "Using fusefs compatibility mode" do
	describe FuseFS do
		
		it "should indicate FuseFS compatibility" do
			FuseFS::RFUSEFS_COMPATIBILITY.should == false
		end
		
		it "should use FuseFS compatible raw calls" 
	end
end
