# frozen_string_literal: true

require 'rails_helper'

# Ensure the Selaenium Ruby client binding from /tmp/selaenium/ruby is loaded
$LOAD_PATH.unshift '/tmp/selaenium/ruby/lib'
require 'selenium-webdriver'

RSpec.describe 'Selaenium Component Integration', type: :component do
  describe 'Selaenium Engine Routing & Protocol Mapping' do
    it 'correctly maps W3C commands to HTTP routes via the Aether native engine' do
      expect(Selenium::WebDriver.route('get')).to eq('POST /session/:sessionId/url')
      expect(Selenium::WebDriver.route('getCurrentUrl')).to eq('GET /session/:sessionId/url')
      expect(Selenium::WebDriver.route('findElement')).to eq('POST /session/:sessionId/element')
      expect(Selenium::WebDriver.route('executeScript')).to eq('POST /session/:sessionId/execute/sync')
      expect(Selenium::WebDriver.route('quit')).to eq('DELETE /session/:sessionId')
      expect(Selenium::WebDriver.route('non_existent_command')).to eq('')
    end

    it 'maps W3C error strings to stable integer codes' do
      expect(Selenium::WebDriver.error_code('no such element')).to eq(17)
      expect(Selenium::WebDriver.error_code('stale element reference')).to eq(23)
      expect(Selenium::WebDriver.error_code('invalid selector')).to eq(11)
      expect(Selenium::WebDriver.error_code('')).to eq(0)
    end
  end

  describe 'Selaenium Locator Normalization' do
    it 'decodes CSS locators into W3C strategy/value hashes' do
      loc = Selenium::WebDriver.decode_by(Selenium::WebDriver::By::CSS_SELECTOR, '.product-card')
      expect(loc).to eq({ 'using' => 'css selector', 'value' => '.product-card' })
    end

    it 'decodes ID locators with engine-level normalization' do
      loc = Selenium::WebDriver.decode_by(Selenium::WebDriver::By::ID, 'header')
      expect(loc['value']).to include('header')
    end

    it 'supports keyword locators' do
      loc = Selenium::WebDriver.decode_by(id: 'main-nav')
      expect(loc['using']).to be_a(String)
      expect(loc['value']).to include('main-nav')
    end
  end

  describe 'Selaenium FFI Engine & Transport Handlers' do
    it 'exposes Native Fiddle function table bindings over libselenium_core' do
      expect(Selenium::WebDriver::Native.has_symbol?(:open)).to be true
      expect(Selenium::WebDriver::Native.has_symbol?(:execute)).to be true
      expect(Selenium::WebDriver::Native.has_symbol?(:close)).to be true
      expect(Selenium::WebDriver::Native.has_symbol?(:route)).to be true
    end

    it 'handles transport failures gracefully on invalid endpoints' do
      expect do
        Selenium::WebDriver.chrome('http://127.0.0.1:1')
      end.to raise_error(Selenium::WebDriver::WebDriverError) do |err|
        expect(err.code).to eq(-1)
      end
    end
  end
end
