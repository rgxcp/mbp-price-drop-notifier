# frozen_string_literal: true
require 'net/http'
require 'uri'

class PriceDropNotifier
  def initialize
    @seller = {
      ibox: '🔴',
      digimap: '🔴',
      eraspace: '🔴'
    }
  end

  def self.run
    new.run
  end

  def run
    begin
      update_health_check_message
    rescue => e
      log_error(e)
    end

    @seller.each do |seller, _|
      begin
        sleep 1

        seller_name = seller == :ibox ? 'iBox' : seller.capitalize

        response = send("fetch_#{seller}_product_page")
        if response.code == '200'
          @seller[seller] = '🟢'

          begin
            update_health_check_message
          rescue => e
            log_error(e)
          end

          price = send("check_#{seller}_price", response.body)
          judge_send_notification_message_about_price(price, seller)
        else
          text = failed_to_check_price_message_text(seller_name, response.code)

          send_message(text)
        end
      rescue => e
        log_error(e)
      end
    end
  end

  private

  def timestamp
    Time.now.strftime('%-d %B %Y %H:%M:%S')
  end

  def log_error(e)
    log = <<~TEXT.chomp
    #{timestamp}
    #{e.class} - #{e.message}
    #{e.backtrace.join("\n")}
    TEXT
    File.write('price_drop_notifier_logs.txt', log, mode: 'a')
  end

  def token
    # TODO: YOUR TELEGRAM TOKEN HERE
  end

  def chat_id
    # TODO: YOUR TELEGRAM CHAT ID HERE
  end

  def message_id
    # TODO: YOUR TELEGRAM MESSAGE ID HERE
  end

  def health_check_message_text
    <<~TEXT.chomp
    Last run: #{timestamp}

    iBox: #{@seller[:ibox]}
    Digimap: #{@seller[:digimap]}
    Eraspace: #{@seller[:eraspace]}
    TEXT
  end

  def failed_to_check_price_message_text(seller_name, response_code)
    "Failed to perform request to check #{seller_name} price with response code #{response_code}"
  end

  def price_dropped_message_text(seller_name, percentage, price)
    "The #{seller_name} price has been dropped #{percentage}% from its original price to Rp#{price}"
  end

  def buy_it_now_message_text(seller_name, percentage, price)
    <<~TEXT.chomp
    IT'S TIME TO BUY!

    #{price_dropped_message_text(seller_name, percentage, price)}
    TEXT
  end

  def update_health_check_message
    uri = URI("https://api.telegram.org/bot#{token}/editMessageText")

    form = {
      'chat_id' => chat_id,
      'message_id' => message_id,
      'text' => health_check_message_text
    }

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request.body = URI.encode_www_form(form)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
  end

  def send_message(text)
    uri = URI("https://api.telegram.org/bot#{token}/sendMessage")

    form = {
      'chat_id' => chat_id,
      'text' => text
    }

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/x-www-form-urlencoded'
    request.body = URI.encode_www_form(form)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
  end

  def fetch_ibox_product_page
    uri = URI('https://ibox.co.id/product/14-inch-macbook-pro-m3-pro-s8100128517')

    request = Net::HTTP::Get.new(uri)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
  end

  def fetch_digimap_product_page
    uri = URI('https://www.digimap.co.id/products/14-inch-macbook-pro-m3-pro-mrx63id-a')

    request = Net::HTTP::Get.new(uri)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
  end

  def fetch_eraspace_product_page
    uri = URI('https://eraspace.com/eraspace/produk/apple-macbook-pro-m3-pro--m3-max-14-inci-2024')

    request = Net::HTTP::Get.new(uri)

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
  end

  def check_ibox_price(body)
    if body =~ /"special_price":(.*?),/
      return $1.to_f
    end

    if body =~ /"price":(.*?),/
      return $1.to_f
    end

    nil
  end

  def check_digimap_price(body)
    if body =~ /"amount":(.*?),/
      return $1.to_f
    end

    nil
  end

  def check_eraspace_price(body)
    check_ibox_price(body)
  end

  def original_price(seller)
    File.read("#{seller}_prices.txt").split("\n").last.to_f
  end

  def target_price
    # TODO: YOUR TARGET PRICE HERE
  end

  def price_drop_percentage(from:, to:)
    (((to - from) / from) * 100).abs.round
  end

  def judge_send_notification_message_about_price(current_price, seller)
    latest_price = original_price(seller)
    return if current_price >= latest_price

    File.write("#{seller}_prices.txt", current_price, mode: 'a')

    seller_name = seller == :ibox ? 'iBox' : seller.capitalize
    drop_percentage = price_drop_percentage(from: latest_price, to: current_price)
    if current_price > target_price
      text = price_dropped_message_text(seller_name, drop_percentage, current_price)
    else
      text = buy_it_now_message_text(seller_name, drop_percentage, current_price)
    end

    send_message(text)
  end
end
