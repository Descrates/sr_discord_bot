module RunTracker
  module Util
    MaxInteger = 2**(64 - 2) - 1

    @API_CALLS = 0 
    @LAST_API_CALL = DateTime.now # once we exceed >=1 minute, reset throttle
    LIMIT_CALLS = 75

    ##
    # Retrives JSON given a url
    # Returns the parsed JSON object
    def self.jsonRequest(url)
      if secondDifference(DateTime.now, @LAST_API_CALL) > 60
        # Reset the throttle
        @LAST_API_CALL = DateTime.now
        @API_CALLS = 0
      elsif @API_CALLS > LIMIT_CALLS
        Stackdriver.log("Waiting so API can catch back up")
        # Sleep the required number of seconds to reset the counter
        sleep(secondDifference(DateTime.now, @LAST_API_CALL))
        @LAST_API_CALL = DateTime.now
        @API_CALLS = 0
      end

      Stackdriver.log("[JSON] #{url}")
      jsonURI = URI(url)
      response = Net::HTTP.get(jsonURI)
      begin
        response = JSON.parse(response)
      rescue JSON::ParserError => e
        # Failure, try again
        Stackdriver.log("Speedrun.com API Failure, responded with Invalid JSON", level = :ERROR)
        return jsonRequest(url)
      end
      @API_CALLS += 1
      return response
    end

    ##
    # Returns the number of seconds between two DateTime objects
    def self.secondDifference(new_time, old_time)
      ((new_time - old_time) * 24 * 60 * 60).to_i
    end

    ##
    # Returns a random string with the given length
    def self.genRndStr(len)
      (0...len).map { (65 + rand(26)).chr }.join
    end

    ##
    # Given a time in seconds, gives the next lowest minute milestone in seconds
    # For example, given 1:04:01, the next milestone would be 1:03:59
    def self.nextMilestone(time)
      # If you didnt already know, there are 60 seconds in a minute
      # Therefore we can just round down to the nearest 60 seconds - 1
      time / 60 * 60 - 1
    end

    ##
    # Given a time in seconds, gives the current milestone
    # For example, given 1:04:01, means Sub 1:04
    def self.currentMilestoneStr(achievedMilestone)
      achievedMilestone += 1
      minutes = achievedMilestone / 60
      hours = minutes / 60
      minutes = minutes - (hours * 60)
      return sprintf('Sub %02d:%02d', hours, minutes)
    end

    ##
    # Given the composite key for the category, return its subcategory componenets
    def self.getSubCategoryVar(key)
      subComponent = key.split('-').last.split(':')
      [subComponent.first, subComponent.last]
    end

    ##
    # Given a very long string, will split it so it is under the 5000 character limit
    def self.sendBulkMessage(message)
      if message.length <= 5000
        RTBot.send_message(DevChannelID, message)
      else
        multipleMessages = message.scan(/.{1,5000}/) # divides into strings every 5000characters
        multipleMessages.each do |msg|
          RTBot.send_message(DevChannelID, msg)
        end
      end
    end

    ##
    # Given potentially many strings, surround them in a codeblock and return that string
    # Lines must be under 2000 characters long as that is not guaranteed here
    def self.codeBlock(*lines, highlighting: '') # This is a variadic function
      message = "```#{highlighting}\n" # Start of Code block
      lines.each do |line|
        message += "#{line}\n"
      end
      message += '```'
      message
    end # End self.codeBlock

    ##
    # Given an array of lines, do the same as self.codeBlock
    def self.arrayToCodeBlock(lines, highlighting: '') # This is a variadic function
      message = "```#{highlighting}\n" # Start of Code block
      lines.each do |line|
        message += "#{line}\n"
      end
      message += '```'
      message
    end # End self.arrayToCodeBlock

    ##
    # Given an array of lines, make a message
    def self.arrayToMessage(lines) # This is a variadic function
      message = ""
      lines.each do |line|
        message += "#{line}\n"
      end
      message
    end # End self.arrayToCodeBlock

    ##
    # Given an array of lines, make a message, guarantees character limit
    def self.safeArrayToMesage(lines, event) # This is a variadic function
      characterCount = 0
      message = ""
      lines.each do |line|
        characterCount += line.length
        if characterCount > 2000
          event.respond(message) # NOTE untested, this may not work, may have to do a hard RTBot.send_message
          characterCount = 0
          message = ""
        end
        message += "#{line}\n"
      end
      message
    end # End self.arrayToCodeBlock

    ##
    # Given seconds, turns it into time
    def self.secondsToTime(seconds)
      minutes = seconds / 60
      seconds = seconds % 60
      hours = minutes / 60
      minutes = minutes - (hours * 60)
      return sprintf('%02d:%02d:%02d', hours, minutes, seconds)
    end # end of secondsToTime
  end
end
