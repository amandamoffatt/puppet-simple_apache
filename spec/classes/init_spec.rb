require 'spec_helper'
describe 'simple_apache' do
  context 'with default values for all parameters' do
    it { should contain_class('simple_apache') }
  end
end
