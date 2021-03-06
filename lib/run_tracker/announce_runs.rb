module RunTracker
  module AnnounceRuns

    def self.announceRuns

      # Loop through all of the tracked games
      trackedGames = SQLiteDB.getTrackedGames
      if trackedGames == nil
        return
      end
      trackedGames.each do |trackedGame|
        # Get any unverified runs for this game
        requestLink = "#{SrcAPI::API_URL}runs" \
                      "?game=#{trackedGame.id}" \
                      '&status=verified&orderby=verify-date&direction=desc'

        Util.jsonRequest(requestLink)['data'].each do |run|
          # Check to see if the run has already been announced before
          check = SQLiteDB::Conn.execute("SELECT * FROM announcements WHERE run_id = '#{run['id']}'")
          if check.length > 0
            next
          end

          # If the run is older than a day, ignore it
          # This is kind of a hack, but i dont track individual run ids so no way to properly check
          # This only really affects the first runs after seeding, once this gets going they will be
          # properly avoided
          if (Date.today).jd - Date.strptime(run['status']['verify-date'].split('T').first, '%Y-%m-%d').jd > 1
            next
          end

          # handle guest accounts
          runnerName = run['players'].first['id']
          if !run['players'].first['rel'].casecmp('guest').zero?
            runnerName = SrcAPI.getUserName(runnerName)
            runnerKey = run['players'].first['id']
          else
            runnerKey = run['players'].first['name'].downcase
          end

          category = nil
          # Figure out the games category
          trackedGame.categories.each do |hashKey, cat|
            # first check to see if it is the right category, regardless of subcategory
            categoryID = hashKey.split('-').first
            if categoryID.casecmp(run['category']).zero?
              # k then need to check the sub-category portion
              if hashKey.casecmp("#{run['category']}-:").zero?
                category = cat
                break
              end
              variableID = hashKey.split('-').last.split(':').first
              subcatID = hashKey.split('-').last.split(':').last
              if run['values'].key?(variableID) && run['values'][variableID].casecmp(subcatID).zero?
                category = cat
                break
              end
            end
          end # end of category loop

          if category == nil
            Stackdriver.log("Category was null when looking for it when announcing new run #{run['category']}", :ERROR)
            return #TODO: i feel like this is bad, why would the category be nil?
          end

          # Handle non video links
          videoLink = "No Video"
          if run['videos'].key?('links')
            videoLink = run['videos']['links'].first['uri']
          end

          # TODO: alot of the stuff below should be moved to a seperate method, but it works and im afraid
          # Try to get the runner object from database
          runner = SQLiteDB.getCurrentRunner(run['players'].first['id'])
          addNewRunner = false
          # If new runner or first run in this category, say this is his first run
          firstRun = false
          if runner == nil
            runner = Runner.new(runnerKey, runnerName)
            runner.historic_runs[trackedGame.id] = RunnerGame.new(trackedGame.id, trackedGame.name)
            runner.historic_runs[trackedGame.id].categories[category.category_id] = RunnerCategory.new(category.category_id, category.category_name)
            firstRun = true
            addNewRunner = true
          end

          embed = Discordrb::Webhooks::Embed.new(
              # TODO: author information = runner
              # thumbnail = game avatar
              title: "Newly Verified Run for - #{trackedGame.name} in #{category.category_name}",
              url: run['weblink'],
              author: { 
                name: runnerName,
                url: "https://www.speedrun.com/user/#{runnerName}",
                icon_url: runner.avatar_url
              },
              thumbnail: {
                url: trackedGame.cover_url
              },
              footer: {
                text: "#{PREFIX}help to view a list of available commands"
              }
          )
          embed.colour = "#fff200"
          embed.add_field(
            name: "Runner",
            value: runnerName,
            inline: false
          )
          embed.add_field(
            name: "Time",
            value: Util.secondsToTime(run['times']['primary_t']),
            inline: false
          )

          # Has this runner ran this game before, init the game and category
          if !runner.historic_runs.key?(trackedGame.id)
            firstRun = true
            runner.historic_runs[trackedGame.id] = RunnerGame.new(trackedGame.id, trackedGame.name)
            runner.historic_runs[trackedGame.id].categories[category.category_id] = RunnerCategory.new(category.category_id, category.category_name)
          # If the runner has ran the game before, but not the category yet
          elsif !runner.historic_runs[trackedGame.id].categories.key?(category.category_id)
            firstRun = true
            runner.historic_runs[trackedGame.id].categories[category.category_id] = RunnerCategory.new(category.category_id, category.category_name)
          end # else its fine

          # Increment the runners stats
          category.number_submitted_runs += 1
          runner.num_submitted_runs += 1
          runner.total_time_overall += Integer(run['times']['primary_t'])
          runner.historic_runs[trackedGame.id].num_submitted_runs += 1
          runner.historic_runs[trackedGame.id].total_time_overall += Integer(run['times']['primary_t'])
          runner.historic_runs[trackedGame.id].categories[category.category_id].num_submitted_runs += 1
          runner.historic_runs[trackedGame.id].categories[category.category_id].total_time_overall += Integer(run['times']['primary_t'])

          # Check if the run is a new milestone for this runner
          runnerCurrentPB = runner.historic_runs[trackedGame.id].categories[category.category_id].current_pb_time
          nextMilestone = Util.nextMilestone(runnerCurrentPB)
          if runnerCurrentPB == Util::MaxInteger
            runner.historic_runs[trackedGame.id].categories[category.category_id]
                  .milestones['First Run'] = run['weblink']
          elsif nextMilestone >= Integer(run['times']['primary_t'])
            runner.historic_runs[trackedGame.id].categories[category.category_id]
                  .milestones[Util.currentMilestoneStr(nextMilestone)] = run['weblink']
          end

          newPB = false
          pbDiff = 0
          # Update if PB
          if Integer(run['times']['primary_t']) < runner.historic_runs[trackedGame.id].categories[category.category_id].current_pb_time
            newPB = true
            pbDiff = runner.historic_runs[trackedGame.id].categories[category.category_id].current_pb_time - Integer(run['times']['primary_t'])
            runner.historic_runs[trackedGame.id].categories[category.category_id].current_pb_time = Integer(run['times']['primary_t'])
            runner.historic_runs[trackedGame.id].categories[category.category_id].current_pb_id = run['id']
          end

          # If WR
          if category.current_wr_time > Integer(run['times']['primary_t'])

            category.number_submitted_wrs += 1
            runner.num_submitted_wrs += 1
            runner.historic_runs[trackedGame.id].num_previous_wrs += 1
            runner.historic_runs[trackedGame.id].categories[category.category_id].num_previous_wrs += 1

            runDate = nil
            # If the run has no date, fallback to the verified date
            if !run['date'].nil?
              runDate = Date.strptime(run['date'], '%Y-%m-%d')
            elsif !run['status']['verify-date'].nil?
              # TODO:: cant strp date and time at same time? loses accuracy, fix
              runDate = Date.strptime(run['status']['verify-date'].split('T').first, '%Y-%m-%d') 
            end

            # Get the WR's date
            requestLink = "#{SrcAPI::API_URL}runs/#{run['id']}"
            oldWR = Util.jsonRequest(requestLink)['data']
            oldWRDate = nil
            # If the run has no date, fallback to the verified date
            if !oldWR['date'].nil?
              oldWRDate = Date.strptime(oldWR['date'], '%Y-%m-%d')
            elsif !oldWR['status']['verify-date'].nil?
              # TODO:: cant strp date and time at same time? loses accuracy, fix
              oldWRDate = Date.strptime(oldWR['status']['verify-date'].split('T').first, '%Y-%m-%d') 
            end

            # Before we scrap the old date, see if it's the new longest WR
            if (runDate - oldWRDate).to_i > trackedGame.longest_held_wr_time
              category.longest_held_wr_id = run['id']
              category.longest_held_wr_time = (runDate - oldWRDate).to_i
            end

            category.current_wr_run_id = run['id']
            category.current_wr_time = Integer(run['times']['primary_t'])
          end # end WR IF statement

          # Moderator stuff
          if !run['status']['examiner'].nil?
            modKey = run['status']['examiner']
            # If the moderator is no longer a moderator, create them
            unless trackedGame.moderators.key?(modKey)
              trackedGame.moderators[modKey] = Moderator.new(modKey, SrcAPI.getUserName(modKey))
              trackedGame.moderators[modKey].past_moderator = true
            end

            mod = trackedGame.moderators[modKey]
            mod.total_verified_runs += 1

            # If there is no verify date, skip it
            if run['status']['verify-date'].nil?
              break
            end
            # If the moderator doesnt have a recent verified run date
            if mod.last_verified_run_date.nil?
              mod.last_verified_run_date = Date.strptime(run['status']['verify-date'].split('T').first, '%Y-%m-%d')
            # If the verified date is more recent (epoch, greater is closer)
            elsif mod.last_verified_run_date < Date.strptime(run['status']['verify-date'].split('T').first, '%Y-%m-%d')
              mod.last_verified_run_date = Date.strptime(run['status']['verify-date'].split('T').first, '%Y-%m-%d')
            end
          end # end of moderator stuff check

          # Now that the hell is over, update the database
          if addNewRunner == true
            SQLiteDB.insertNewRunner(runner)
          else
            if newPB == true and firstRun == false
              embed.add_field(
                name: "Time Save from Previous Run",
                value: Util.secondsToTime(pbDiff),
                inline: false
              )
            elsif firstRun == true
              embed.add_field(
                name: "Time Save from Previous Run",
                value: "This is this runner's first run in this category!",
                inline: false
              )
            end
            SQLiteDB.updateCurrentRunner(runner)
          end
          SQLiteDB.updateTrackedGame(trackedGame)
          # Add run to the announcements table so we dont duplicate the messages
          SQLiteDB::Conn.execute("INSERT INTO announcements (run_id) VALUES ('#{run['id']}')")
          RTBot.send_message(trackedGame.announce_channel, "", false, embed)
          RTBot.send_message(trackedGame.announce_channel, "Video Link - #{videoLink}")
        end # end of run loop
      end # end of tracked games loop

    end # end announce runs
  end
end
