# 
# monster.rb
# Home Curious
#
# Created by Donovan on 11/30/2014
# Copyright (c) Donovan. All rights reserved.

require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'json'
require 'dstk'
require 'parse-ruby-client'

Parse.init 	:application_id => "G0xCsIplPFG3SySANERT4h8dPRPJwl6t58RkJMbj",
       			:api_key        => "JLa5DhqrrvEci34i0iU8dNsifFGGJOB2Hr2o6JEu", 
       			:quiet 					=> true | false

HOME_URL                = "http://www.trulia.com"
CITY_STATE_ZIP_REGEX    = /^(.+)[,\\s]+(.+?)\s*(\d{5})?$/
PAGE_LIMIT              = 1000
DELAY_SECONDS						= 5
TEXT_FILE_ROOT_DIR_LIVE = "/var/www/zipcodes"
# TEXT_FILE_ROOT_DIR_LIVE = "/Volumes/Work/zParseCloud/Smith/homeCuriousRubyScraper_Local/zipcodes"
TEXT_FILE_ROOT_DIR_DEV 	= "/Volumes/Work/zParseCloud/Smith/homeCuriousRubyScraper_Local/zipcodes"
RUN_MODE_LIVE 	= "live"
RUN_MODE_DEV 		= "dev"
USER_AGENT 			= "Googlebot-Image/1.0 ( http://www.googlebot.com/bot.html)"

class Monster
	
	def initialize(text_file_name, run_mode, log_class_name="")
		@text_file_name		= text_file_name
		@run_mode			= run_mode
		@number_of_houses   = 0
		@number_of_pages    = 0
		@number_of_zipcodes = 0
		@log_class_name 		= log_class_name
	end

	# Builds text file path based on run_mode
	def build_text_file_path
		return "#{TEXT_FILE_ROOT_DIR_LIVE}/#{@text_file_name}" if @run_mode == RUN_MODE_LIVE
		"#{TEXT_FILE_ROOT_DIR_DEV}/#{@text_file_name}"
	end

	# Check all zipcodes processed once in Class of log_class_name
	def check_all_zipcodes_processed_once(zipcodes)
		return false if @log_class_name.empty?
		delay_request(DELAY_SECONDS)
		results = Parse::Query.new(@log_class_name).tap do |q|
			q.eq("completed", true)
		  q.limit = 0
		  q.count
		end.get
		return results["count"] == zipcodes.length
	end

	# Gets zipcode object in Class of log_class_name
	def get_zipcode_object_logged(zipcode)
		return nil if @log_class_name.empty?
		delay_request(DELAY_SECONDS)
		zipcode_object = Parse::Query.new(@log_class_name).eq("value", zipcode).get.first
	end

	# Checks zipcode is processed once in Class of log_class_name
	def check_zipcode_processed_once(zipcode)
		return false if @log_class_name.empty?
		zipcode_object = get_zipcode_object_logged(zipcode)
		return zipcode_object && zipcode_object["completed"]
	end

	# Checks house of a zipcode already processed in Class of log_class_name
	def check_house_of_zipcode_processed_once(zipcode, property_id)
		return false if @log_class_name.empty?
		delay_request(DELAY_SECONDS)
		zipcode_object = count = Parse::Query.new(@log_class_name).tap do |q|
		  q.eq("value", zipcode)
		  q.eq("propertyIDs", property_id)
		end.get.first
		return !zipcode_object.nil?
	end

	# Saves zipcode in Class of log_class_name of Parse Data Store 
	def save_processing_zipcode(zipcode)
		return if @log_class_name.empty?
		zipcode_object = get_zipcode_object_logged(zipcode)
		return if zipcode_object
		zipcode_object = Parse::Object.new(@log_class_name)
		zipcode_object["value"] = zipcode
		result = zipcode_object.save
		delay_request(DELAY_SECONDS)
	end

	# Saves property_id of a house processed in Class of log_class_name
	def save_propertyID_processed(zipcode, property_id)
		return if @log_class_name.empty?
		zipcode_object = get_zipcode_object_logged(zipcode)
		return if zipcode_object.nil?
		zipcode_object.array_add_unique("propertyIDs", property_id)
		result = zipcode_object.save
		delay_request(DELAY_SECONDS)
	end

	# Sets zipcode with completion of processed once in Class of log_class_name
	def set_zipcode_processing_completed(zipcode)
		return if @log_class_name.empty?
		zipcode_object = get_zipcode_object_logged(zipcode)
		return if zipcode_object.nil?
		zipcode_object["completed"] = true
		result = zipcode_object.save
		delay_request(DELAY_SECONDS)
	end

	# Returns url of a page to be scrapped by a zipcode and page number
	def build_url(zipcode, nPage=1)
	  "#{HOME_URL}/for_sale/#{zipcode}_zip" if nPage == 1
	  "#{HOME_URL}/for_sale/#{zipcode}_zip/#{nPage}_p"
	end

	# Returns HTML Data for a url
	def page_from_url(url)
		delay_request(DELAY_SECONDS)
	  Nokogiri::HTML(open(url, "User-Agent" => USER_AGENT))
	  # Nokogiri::HTML(open(url))

	  # browser = Watir::Browser.new
	  # browser.goto url
	  # html = browser.html
	  # browser.close
	  # Nokogiri::HTML.parse(html)
	end

	# Returns HTML Data by zipcode and page number
	def page_by_zipcode(zipcode, nPage=1)
	  page_from_url build_url(zipcode, nPage)
	end

	# Returns HTML Data containing contacts info by calling ajax url
	def page_for_contacts(property_id)
		delay_request(DELAY_SECONDS)
	  uri = URI.parse("http://www.trulia.com/_ajax/QuickConnect/QuickConnectAjax/?property_id=#{property_id}")
	  res = Net::HTTP.get(uri)
	  res.gsub!("\\n", "")
	  res.gsub!("{\"0\":\"      ", "")
	  res.gsub!("\\", "")
	  res.gsub!("\",\"success\":true,\"errors\":[]}", "")

	  return Nokogiri::HTML(res)
	end

	# Returns the number of pages for a given html page for a zipcode
	def get_number_of_pages(first_page)
	  pages = first_page.css(".srpPagination_page.mhs")
	  if pages.text.empty?
	    tt = first_page.css("div[data-role='listViewNoResults']").text
	    return nil if (!tt.empty?) && (tt.include? "No results were found for your search:")
	  end
	  return pages.at(-1).text.to_i if !pages.nil?
	end

	def get_addresses(house)
	  address1, *address2 = house.css('a.primaryLink.pdpLink strong')[0].text.split(/#/)
	  
	  if address2 && address2.length>0
	    address2 = "##{address2[0]}" 
	  else
	    address2 = ""
	  end
	  address1.strip! if !address1.nil?
	  address2.strip! if !address2.nil?
	  return address1, address2
	end 

	def get_citystatezipcode(house)
	  citystatezipcode = house.css('.typeTruncate.h7.mvn')[0].text
	  CITY_STATE_ZIP_REGEX.match(citystatezipcode)
	  city    = Regexp.last_match(1)
	  state   = Regexp.last_match(2)
	  zipcode = Regexp.last_match(3)
	  city.strip! if city
	  state.strip! if state
	  zipcode.strip! if zipcode
	  return city, state, zipcode
	end

	def get_number_of_rooms(house)
	  # if !house.css('.col.cols4 strong').text.empty?
	  #   numberOfBedrooms  = house.css('.col.cols4 strong')[0].text
	  #   numberOfBathrooms = house.css('.col.cols4 div.h7.mvn')[0].text
	    
	  #   if numberOfBedrooms && numberOfBedrooms.include?("beds")
	  #     numberOfBedrooms.include?("beds")
	  #     numberOfBedrooms["beds"]=""
	  #     numberOfBedrooms = numberOfBedrooms.to_i
	  #   end

	  #   if numberOfBathrooms && numberOfBathrooms.include?("baths")
	  #     numberOfBathrooms["baths"]="" 
	  #     numberOfBathrooms = numberOfBathrooms.to_i
	  #   end
	  # end
	  if !house.css('.col.cols4 strong').text.empty?
	    numberOfBedrooms  = house.css('.col.cols4 strong')[0].text  
	    if numberOfBedrooms && numberOfBedrooms.include?("beds")
	      numberOfBedrooms.include?("beds")
	      numberOfBedrooms["beds"]=""
	      numberOfBedrooms = numberOfBedrooms.to_i
	      numberOfBedrooms = nil if numberOfBedrooms == 0
	    else 
	      numberOfBedrooms = nil
	    end
	  end
	  
	  if !house.css('.col.cols4 div.h7.mvn').text.empty?
	    numberOfBathrooms = house.css('.col.cols4 div.h7.mvn')[0].text
	    if numberOfBathrooms && numberOfBathrooms.include?("baths")
	      numberOfBathrooms["baths"]="" 
	      numberOfBathrooms = numberOfBathrooms.to_i
	      numberOfBathrooms = nil if numberOfBathrooms == 0
	    else
	      numberOfBathrooms = nil
	    end
	  end

	  return numberOfBedrooms, numberOfBathrooms
	end

	def get_squareFeet(house)
	  squareFeet = house.css('.col.cols5.typeTruncate div.h7.mvn').text
	  squareFeet.gsub!("sqft", "")
	  squareFeet.gsub!(",", "")
	  squareFeet = squareFeet.to_i
	  squareFeet = nil if squareFeet == 0
	  return squareFeet
	end

	def get_mls_id(house_detail_page)
	  if house_detail_page.css('.listBulleted.mbn') &&
	     house_detail_page.css('.listBulleted.mbn').length > 1 &&
	     house_detail_page.css('.listBulleted.mbn')[2].css('li') &&
	     house_detail_page.css('.listBulleted.mbn')[2].css('li').length > 0     
	    mls_id = house_detail_page.css('.listBulleted.mbn')[2].css('li')[0].text
	    mls_id.gsub!("MLS/Source ID: ", "")
	  end
	  return mls_id
	end

	def get_description(house_detail_page)
		if house_detail_page.css("span[itemprop='description']") && 
			 house_detail_page.css("span[itemprop='description']").length > 0 && 
			 house_detail_page.css("span[itemprop='description']")[0].text
	  		description = house_detail_page.css("span[itemprop='description']")[0].text
	  		description.strip! if description
	  		description.gsub!("\"", "") if description && description.include?("\"")
	  end
	  return description
	end

	def get_price_and_isForSale(house_detail_page)
	  isForSale = true
	  price = house_detail_page.css("span[itemprop='price']")[0].text
	  if price
	    price["$"]=""
	    price.gsub!(/,/, '')
	    price.gsub!("From ", "") if price.include?("From ")
	    price = price.to_i
	  else
	    isForSale = false
	  end
	  return price, isForSale
	end

	def get_price_and_isForSale2(house)
	  isForSale = true
	  price = house.css(".col.cols8.lastCol.txtR").text
	  if price
	    price.strip!
	    price["$"]="" if price.include?("$")
	    price.gsub!(/,/, '') if price.include?(",")
	    price.gsub!("\"", "") if price.include?("\"")
	    price = price.to_i
	    price = nil if price == 0
	  else
	    isForSale = false
	  end
	  return price, isForSale
	end

	def get_agent_Name_imageURL_phoneNumber(house_detail_page, property_id)
	  agent_data = house_detail_page.css(".contact_module.mbl")
	  if !agent_data.text.empty? && !agent_data.css(".mediaBody a").text.empty?
	    agentName = agent_data.css(".mediaBody a").text.strip!
	    if  agent_data.css(".mediaBody img") &&
	        agent_data.css(".mediaBody img").length>0 &&
	        agent_data.css(".mediaBody img")[0]["src"]
	      agentImageURL = agent_data.css(".mediaBody img")[0]["src"]
	    elsif agent_data.css(".mediaImg.mrs.prn img") &&
	          agent_data.css(".mediaImg.mrs.prn img").length > 0
	          agent_data.css(".mediaImg.mrs.prn img")[0]["src"]
	      agentImageURL = agent_data.css(".mediaImg.mrs.prn img")[0]["src"]
	    end
	    agentPhoneNumber = agent_data.css(".property_contact_field.h7.man").text.strip!
	  else
	    agent_data = page_for_contacts(property_id).css("div.agent_row")
	    if !agent_data.text.empty?
	      agentName 				= agent_data.css("a.name_link.typeEmphasize")[0].text.strip!
	      agentImageURL 		= agent_data.css("img.profileImage.small.txtT.mrs")[0]['src']
	      agentPhoneNumber 	= agent_data.css(".phone.col.cols7.pln")[0].text.strip!
	    end
	  end

	  if agentName.nil? && agentImageURL.nil? && agentPhoneNumber.nil?
	  	agent_data 			 = house_detail_page.css(".box.boxHighlight.pal.mvm")
	  	if agent_data
	  		if agent_data.css(".media .mediaImg img") && agent_data.css(".media .mediaImg img").length>0 &&
	  			 agent_data.css(".media .mediaImg img")[0]["src"]
	  			agentImageURL 	 = agent_data.css(".media .mediaImg img")[0]["src"]	 
	  		end
				
				if agent_data.css(".col.colExt.lastCol .col.pln div") && 
					 agent_data.css(".col.colExt.lastCol .col.pln div").length > 1
					agentName 			 = agent_data.css(".col.colExt.lastCol .col.pln div")[0].text.strip!
					agentPhoneNumber = agent_data.css(".col.colExt.lastCol .col.pln div")[1].text
				end
			end
	  end
	  return agentName, agentImageURL, agentPhoneNumber
	end

	def get_imageURLs(house_detail_page)
	  imageURLs = Array.new
	  # house_detail_page.css(".photoPlayerThumbnailImg.man.pan.baz").each do |img|
	  # puts house_detail_page
	  house_detail_page.css(".photoPlayerThumbnailImg").each do |img|
	    imageURLs.push(img['src'])
	  end

	  if imageURLs.length == 0
	  	if house_detail_page.css(".photoPlayerCurrentItemContainer img")
	  		data = house_detail_page.css(".photoPlayerCurrentItemContainer img")
	  		if data.length > 0 && data[0]["src"]
	  			imageURLs.push(data[0]["src"])
	  		end
	  	end
	  end

	  return imageURLs
	end

	def get_latitude_longitude(address1, city, state, zipcode)
	  # puts url_escape("http://www.datasciencetoolkit.org/street2coordinates/#{address1}, #{city}, #{state}, #{zipcode}")
	  begin
		  # uri = URI.parse(url_escape("http://www.datasciencetoolkit.org/street2coordinates/#{address1}, #{city}, #{state}, #{zipcode}"))
		  # res = Net::HTTP.get(uri)
		  # res = JSON.parse(res)
		  dstk 	= DSTK::DSTK.new
		  key 	= "#{address1}, #{city}, #{state} #{zipcode}"
		  res 	= dstk.street2coordinates(key)
		  if res[key]
		    latitude  = res[key]["latitude"]
		    longitude = res[key]["longitude"]
		  end
		rescue => err
			puts "Exception: #{err}"
      # err
	  end
	  return latitude, longitude
	end

	# Delay 1.5 seconds
	def delay_request(seconds, keyword="")
	  # puts "Current time: #{Time.now}"
    # puts "Sleeping for #{seconds} seconds for the next #{keyword} processing...."
    sleep(seconds)
	end

	# Returns a house
	def get_house(house)
		# puts "Current time: #{Time.now}"
	  property_id = house["data-property-id"]
	  puts "\r\nproperty_id: #{property_id}"

	  pageURL = HOME_URL + house.css('a.primaryLink.pdpLink')[0]['href']
	  puts "pageURL: #{pageURL}"

	  price, isForSale = get_price_and_isForSale2(house)
	  # puts "price: #{price}"
	  # puts "isForSale: #{isForSale}"

	  address1, address2 = get_addresses(house)
	 
	  # puts "address1: #{address1}"
	  # puts "address2: #{address2}"
	  
	  city, state, zipcode = get_citystatezipcode(house)
	  # puts "city: #{city}"
	  # puts "state: #{state}"
	  # puts "zipcode: #{zipcode}"

	  if zipcode && !zipcode.empty? && check_house_of_zipcode_processed_once(zipcode, property_id)
	  	puts "This house already processed once. no need to proceed."
	  	return
	  end

	  # Check if a house object with the property_id is already existing
	  house_object = get_house_object_by_propertyID(property_id)
	  if house_object

	  	# Checks MLS_ID undefined then deletes it.
	  	if house_object["MLS_ID"].nil?
	  		puts "Deleted house without MSL_ID for pageURL : #{house_object['pageURL']}"
	  		result = house_object.parse_delete
	  		delay_request(DELAY_SECONDS)
	  		save_propertyID_processed(zipcode, property_id)
	  		return
	  	end

	  	bPriceUpdated 			= false
	  	bLocationUpdated 		= false
	  	bImageURLsUpdated 	= false
	  	bDescriptionUpdated = false
	  	bContactInfoUpdated = false

	    if house_object["price"] != price
	      house_object["price"] = price
	      if price.nil?
	        house_object["isForSale"] = false
	      else
	      	house_object["isForSale"] = true
	      end
	      bPriceUpdated = true
	    end

	    if house_object["houseLocation"].nil?
	    	latitude, longitude = get_latitude_longitude(address1, city, state, zipcode)
		  	puts "coordinates: #{latitude}, #{longitude}"
		  	if !latitude.nil? && !longitude.nil?
		  		house_object["houseLocation"]     = Parse::GeoPoint.new({
	                              "latitude" => latitude, 
	                              "longitude" => longitude}) if !latitude.nil? && !longitude.nil?
		  		bLocationUpdated = true
		  	end
	    end

	    house_detail_page = page_from_url(pageURL)

	    if house_object["imageURLs"].nil?
	    	imageURLs = get_imageURLs(house_detail_page)
	    	if imageURLs && imageURLs.length > 0
	    		house_object["imageURLs"] = imageURLs
	    		bImageURLsUpdated = true
	    	end
	    end

	    if house_object["description"].nil?
	    	description = get_description(house_detail_page)
	    	if description && !description.empty?
	    		house_object["description"] = description 
	    		bDescriptionUpdated = true
	    	end
	    end

	    if house_object["agentName"].nil?
	    	agentName, agentImageURL, agentPhoneNumber = get_agent_Name_imageURL_phoneNumber(house_detail_page, property_id)
	    	if agentName && !agentName.empty?
	    		house_object["agentName"]         = agentName if agentName && !agentName.empty?
				  house_object["agentImageURL"]     = agentImageURL if agentImageURL && !agentImageURL.empty?
				  house_object["agentPhoneNumber"]  = agentPhoneNumber if agentPhoneNumber && !agentPhoneNumber.empty?
		    	bContactInfoUpdated = true
		    end
	    end

	    if bPriceUpdated == true || bLocationUpdated == true || bImageURLsUpdated == true || bDescriptionUpdated == true || bContactInfoUpdated == true
	    	puts "Updated the existing house with isForeSale: #{house_object['isForSale']}, price: #{house_object['price']}" if bPriceUpdated
	    	puts "Updated the existing house with coordinates: #{latitude}, #{longitude}" if bLocationUpdated
	    	puts "Updated the existing house with imageURLs: #{imageURLs}" if bImageURLsUpdated
	    	puts "Updated the existing house with description: #{description}" if bDescriptionUpdated
	    	puts "Updated the existing house with contact: #{agentName}, #{agentImageURL}, #{agentPhoneNumber}"
	    	result = house_object.save
	    	delay_request(DELAY_SECONDS)
	    	save_propertyID_processed(zipcode, property_id) if result
	    	return
	    end
	    
	    puts "The house already existing and not changed any info."
	    delay_request(DELAY_SECONDS)
	    save_propertyID_processed(zipcode, property_id)
	    return
	  end

	  numberOfBedrooms, numberOfBathrooms = get_number_of_rooms(house)
	  # puts "numberOfBedrooms: #{numberOfBedrooms}"
	  # puts "numberOfBathrooms: #{numberOfBathrooms}"

	  squareFeet = get_squareFeet(house)
	  # puts "squareFeet: #{squareFeet}"

	  house_detail_page = page_from_url(pageURL) if house_detail_page.nil?

	  mls_id = get_mls_id(house_detail_page)
	  puts "MLS_ID: #{mls_id}"
	  if mls_id.nil? || (mls_id && mls_id.empty?)
	  	puts "No need to save house without MLS_ID for pageURL: #{pageURL}"
	  	delay_request(DELAY_SECONDS)
	  	save_propertyID_processed(zipcode, property_id)
	  	return
	  end

	  description = get_description(house_detail_page)
	  # puts "description: #{description}"

	  # latitude 	= nil
	  # longitude = nil
	  if latitude.nil? && longitude.nil?
	  	latitude, longitude = get_latitude_longitude(address1, city, state, zipcode)
	  	# puts "coordinates: #{latitude}, #{longitude}"
	  end
	  
	  # price, isForSale = get_price_and_isForSale(house_detail_page)
	  # puts "price: #{price}"
	  # puts "isForSale: #{isForSale}"

	  agentName, agentImageURL, agentPhoneNumber = get_agent_Name_imageURL_phoneNumber(house_detail_page, property_id)
	  # puts "agentName: #{agentName}"
	  # puts "agentImageURL: #{agentImageURL}"
	  # puts "agentPhoneNumber: #{agentPhoneNumber}"

	  imageURLs = get_imageURLs(house_detail_page)
	  # puts "imageURLs(#{imageURLs.count}): \r\n #{imageURLs.join("\r\n")}"

	  # Save new house object
	  house_object = Parse::Object.new("House")
	  house_object["propertyID"]        = property_id if property_id && !property_id.empty?
	  house_object["pageURL"]           = pageURL if pageURL && !pageURL.empty?
	  house_object["address1"]          = address1 if address1 && !address1.empty?
	  house_object["address2"]          = address2 if address2 && !address2.empty?
	  house_object["city"]              = city if city && !city.empty?
	  house_object["state"]             = state if state && !state.empty?
	  house_object["zipcode"]           = zipcode if zipcode && !zipcode.empty?
	  house_object["numberOfBedrooms"]  = numberOfBedrooms if numberOfBedrooms && numberOfBedrooms > 0
	  house_object["numberOfBathrooms"] = numberOfBathrooms if numberOfBathrooms && numberOfBathrooms > 0
	  house_object["price"]             = price if price && price > 0
	  house_object["isForSale"]         = isForSale
	  house_object["squareFeet"]        = squareFeet if squareFeet && squareFeet > 0
	  house_object["MLS_ID"]            = mls_id if mls_id && !mls_id.empty?
	  house_object["description"]       = description if description && !description.empty?
	  house_object["agentName"]         = agentName if agentName && !agentName.empty?
	  house_object["agentImageURL"]     = agentImageURL if agentImageURL && !agentImageURL.empty?
	  house_object["agentPhoneNumber"]  = agentPhoneNumber if agentPhoneNumber && !agentPhoneNumber.empty?
	  house_object["imageURLs"]         = imageURLs if imageURLs && imageURLs.length > 0
	  house_object["houseLocation"]     = Parse::GeoPoint.new({
	                              "latitude" => latitude, 
	                              "longitude" => longitude}) if !latitude.nil? && !longitude.nil?
	  delay_request(DELAY_SECONDS)
	  result = house_object.save
	  delay_request(DELAY_SECONDS)
  	save_propertyID_processed(zipcode, property_id) if result
	  # puts "Created a new house" if result
	  # puts "Created a new house: #{result}" if result
	end

	def url_escape(basic_string)
	  basic_string = basic_string.gsub(" ", "+")
	  basic_string = basic_string.gsub(",", "%2c")
	  return basic_string
	end

	# Returns a list of scrapped houses from a data
	def get_list_of_items_from_page(page)
	  houses = page.css(".propertyCard.property-data-elem")
	  # puts "NUMBER OF HOUSES: #{houses.length}"

	  houses.each do |house| 
	    get_house(house)
	    @number_of_houses = @number_of_houses + 1
	    puts "Number of Houses Processed : #{@number_of_houses}\r\n"
	    break if @run_mode != RUN_MODE_LIVE
	  end
	end

	# Returns a list of scrapped houses for a zipcode
	def get_house_list_by_zipcode(zipcode)
		save_processing_zipcode(zipcode)
		delay_request(DELAY_SECONDS)

	  page      = page_by_zipcode(zipcode)
	  numPages  = get_number_of_pages(page)

	  if numPages.nil?
	    puts "No Results found for zipcode: #{zipcode}"
	    set_zipcode_processing_completed(zipcode)
	    return false
	  end

	  puts "NUMBER OF PAGES: #{numPages} (zipcode :#{zipcode})"

	  numPages.times do |nPage|
	    page = page_by_zipcode(zipcode, nPage) if nPage > 1
	    get_list_of_items_from_page(page)
	    @number_of_pages += 1
	    puts "Number of Pages Processed: #{@number_of_pages}"
	    break if @run_mode != RUN_MODE_LIVE
	  end
	  set_zipcode_processing_completed(zipcode)
	  delay_request(DELAY_SECONDS)
	  return true
	end

	# Returns all zipcodes from a file
	def get_zipcodes_from_file
	  zipcodes = Array.new
	  counter = 1
	  begin
	      file = File.new(build_text_file_path, "r")
	      while (line = file.gets)
	          # puts "#{counter}: #{line}"
	          # counter = counter + 1
	          line.gsub!("\r\n", "")
	          zipcodes.push(line)
	      end
	      file.close
	  rescue => err
	      puts "Exception: #{err}"
	      # err
	  end
	  return zipcodes
	end

	# Query from Parse

	# Finds a house by MLS_ID
	def get_house_object_by_MLS_ID(mls_id)
		delay_request(DELAY_SECONDS)
	  house = Parse::Query.new("House").eq("MLS_ID", mls_id).first
	  return house
	end

	# Finds a house by propertyID
	def get_house_object_by_propertyID(property_id)
		delay_request(DELAY_SECONDS)
	  house = Parse::Query.new("House").eq("propertyID", property_id).get.first
	  return house
	end

	# Main point for scrap
	def do_start
	  zipcodes = get_zipcodes_from_file
	  zipcodes.shuffle!
	  # puts zipcodes

	  if check_all_zipcodes_processed_once(zipcodes)
	  	puts "All zipcodes already processed once! Thereby no need to proceed."
	  	return
	  end

	  $i=0
	  zipcodes.each do |zipcode|
	  	puts "Processing zipcode : #{zipcode}..."
	  	if check_zipcode_processed_once(zipcode)
	  		puts "#{zipcode} already processed once."
	  	else
		    result = get_house_list_by_zipcode(zipcode) #if $i > 25000
		    if result == true
		      @number_of_zipcodes+=1
		      puts "Number of zipcodes processed: #{@number_of_zipcodes}"
		      break if @run_mode != RUN_MODE_LIVE
		    end
		    $i+=1
		  end
	  end

	  puts "Total Number of Zipcodes: #{zipcodes.length}"
	  puts "Number of zipcodes processed: #{@number_of_zipcodes}"
	  puts "Number of Pages Processed : #{@number_of_pages}\r\n"
	  puts "Number of Houses Processed : #{@number_of_houses}\r\n"
	end

	def check_house_for_updates(property_id, house_detail_page)
		# Check if a house object with the property_id is already existing
	  house_object = get_house_object_by_propertyID(property_id)
	  if house_object
	  	bImageURLsUpdated		= false
	  	bDescriptionUpdated = false

	    if house_object["imageURLs"].nil?
	    	imageURLs = get_imageURLs(house_detail_page)
	    	if imageURLs && imageURLs.length > 0
	    		house_object["imageURLs"] = imageURLs
	    		bImageURLsUpdated = true
	    	end
	    end

	    if house_object["description"].nil?
	    	description = get_description(house_detail_page)
	    	if description && !description.empty?
	    		house_object["description"] = description 
	    		bDescriptionUpdated = true
	    	end
	    end

	    if bImageURLsUpdated || bDescriptionUpdated
	    	puts "Updated the existing house with imageURLs: #{imageURLs}" if bImageURLsUpdated
	    	puts "Updated the existing house with description: #{description}" if bDescriptionUpdated
	    	# house_object.save
	    	return
	    end

	    puts "The house already existing and not changed any info."
	    return
	  end
	end

	def get_second_contact_info(house_detail_page)
		agent_data = house_detail_page.css(".box.boxHighlight.pal.mvm")
		agentImageURL = agent_data.css(".media .mediaImg img")[0]["src"]
		puts "imageurl: #{agentImageURL}"
		agentName = agent_data.css(".col.colExt.lastCol .col.pln div")[0].text.strip!
		puts "agentName: #{agentName}"
		agentPhoneNumber = agent_data.css(".col.colExt.lastCol .col.pln div")[1].text
		puts "agentPhoneNumber: *#{agentPhoneNumber}*"
	end
end