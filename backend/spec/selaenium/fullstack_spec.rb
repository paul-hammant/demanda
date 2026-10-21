# frozen_string_literal: true

require 'rails_helper'
require 'webrick'

$LOAD_PATH.unshift '/tmp/selaenium/ruby/lib'
require 'selenium-webdriver'

RSpec.describe 'Selaenium Full Stack Web Driver Integration', type: :integration do
  before(:all) do
    # Ensure Chrome 145 compatible ChromeDriver is at the head of PATH
    chromedriver_dir = '/home/jules/.cache/selenium/chromedriver/linux64/145.0.7632.117'
    ENV['PATH'] = "#{chromedriver_dir}:#{ENV['PATH']}" if File.directory?(chromedriver_dir)

    # Start a local HTTP server serving Demanda e-commerce pages and components
    @port = 9876
    @server = WEBrick::HTTPServer.new(
      Port: @port,
      Logger: WEBrick::Log.new(nil, 0),
      AccessLog: []
    )

    @server.mount_proc '/' do |_req, res|
      res.status = 200
      res['Content-Type'] = 'text/html'
      res.body = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Demanda E-Commerce Store</title>
        </head>
        <body>
          <header>
            <h1 id="site-title">Demanda Admin & Storefront</h1>
          </header>
          <main>
            <form id="search-form" action="/search" method="get">
              <label for="query">Search Products:</label>
              <input type="text" id="query" name="q" placeholder="Enter product name..." />
              <button type="submit" id="search-btn">Search</button>
            </form>

            <div id="products-list" class="catalog">
              <div class="product-item" data-id="1">
                <span class="product-name">Leather Wallet</span>
                <span class="product-price">$29.99</span>
              </div>
              <div class="product-item" data-id="2">
                <span class="product-name">Canvas Backpack</span>
                <span class="product-price">$59.99</span>
              </div>
            </div>
          </main>
        </body>
        </html>
      HTML
    end

    @server_thread = Thread.new { @server.start }
    sleep 0.5
  end

  after(:all) do
    @server&.shutdown
    @server_thread&.join(2)
  end

  let(:driver) do
    Selenium::WebDriver.for(:chrome, options: {
      'goog:chromeOptions' => {
        'args' => ['--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage']
      }
    })
  end

  after do
    driver&.quit
  end

  describe 'Full Stack Navigation & Element Interactions' do
    it 'navigates to Demanda e-commerce application page and verifies title' do
      driver.get("http://127.0.0.1:#{@port}/")
      expect(driver.title).to eq('Demanda E-Commerce Store')
    end

    it 'locates elements by ID and inspects text content' do
      driver.get("http://127.0.0.1:#{@port}/")
      header = driver.find_element(id: 'site-title')
      expect(header.text).to eq('Demanda Admin & Storefront')
    end

    it 'interacts with form inputs and submits queries' do
      driver.get("http://127.0.0.1:#{@port}/")
      search_input = driver.find_element(id: 'query')
      search_input.send_keys('Canvas Backpack')
      expect(search_input.attribute('value')).to eq('Canvas Backpack')
    end

    it 'queries catalog product items using CSS selector and class locators' do
      driver.get("http://127.0.0.1:#{@port}/")
      products = driver.find_elements(css: '.product-name')
      product_names = products.map(&:text)
      expect(product_names).to include('Leather Wallet', 'Canvas Backpack')
    end

    it 'executes JavaScript in page context via Selaenium engine' do
      driver.get("http://127.0.0.1:#{@port}/")
      product_count = driver.execute_script("return document.querySelectorAll('.product-item').length;")
      expect(product_count).to eq(2)
    end
  end
end
