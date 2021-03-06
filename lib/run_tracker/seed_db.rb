module RunTracker
  module SeedDB
    ##
    # TODO: this needs to be significantly refactored after it works
    # Gathers all of the runners, their runs, their current stats
    # At the same time it also counts the moderators verified runs, and last verified run date
    # Also determines the current stats for each category
    # Will pull all current data from a game's leaderboard
    # categoryList and modList are expected to be hashes keyed with their respective SRC ids
    def self.getGameRunners(gameID, gameName, categoryList, modList)
      currentRunnerList = SQLiteDB.getCurrentRunners
      newRunnerList = {}

      categoryList.each do |_key, category| # Loop through every category
        currentWRTime = Util::MaxInteger
        currentWRID = ''
        currentWRDate = nil

        numSubmittedRuns = 0
        numSubmittedWRs = 0

        longestHeldWR = 0
        longestHeldWRID = ''

        requestLink = "#{SrcAPI::API_URL}runs" \
                      "?game=#{gameID}" \
                      "&category=#{category.category_id.split('-').first}" \
                      '&status=verified&orderby=date&direction=asc&max=200'

        loop do
          # This inefficiency makes me so depressed, the way SRC has added subcategories makes me cry
          # as you cannot do an API call for just a subcategories' runs
          # Remove the subcategory component of the key
          requestResults = Util.jsonRequest(requestLink)
          categoryRuns = requestResults['data']
          pagination = requestResults['pagination']

          categoryRuns.each do |run|
            # Add to runner information
            # NOTE this causes a problem if the runner ever gets a SRC account in the future
            # the fix is probably to check on the heartbeat updating if their name overwrite the previous guest name and then update accordingly
            runnerKey = ''
            runnerName = ''
            if run['players'].first['rel'].downcase.casecmp('guest').zero?
              runnerKey = run['players'].first['name'].downcase
              runnerName = 'guest'
            else
              runnerKey = run['players'].first['id']
            end
            # If we havnt started tracking this runner before, init
            runner = nil
            if !currentRunnerList.key?(runnerKey) && !newRunnerList.key?(runnerKey)
              unless runnerName.downcase.casecmp('guest').zero? # only call API for name if new runner and not a guest
                runnerName = SrcAPI.getUserName(runnerKey)
              end
              runner = Runner.new(runnerKey, runnerName)
              runner.historic_runs[gameID] = RunnerGame.new(gameID, gameName)
              runner.historic_runs[gameID].categories[category.category_id] = RunnerCategory.new(category.category_id, category.category_name)
              newRunnerList[runnerKey] = runner
            elsif newRunnerList.key?(runnerKey)
              runner = newRunnerList[runnerKey]
            else
              runner = currentRunnerList[runnerKey]
            end

            # Check if this run is for the subcategory we are looking for right now
            # If the run has no subcategories, then it changes nothing here (i hope)
            # anything in the variables section will be unrelated, or a new change, in which case, delete and add the game again to update schema
            if category.subcategories != nil && !category.subcategories.empty? &&
               run['values'][Util.getSubCategoryVar(category.category_id).first] != Util.getSubCategoryVar(category.category_id).last
              next # skip the run
            end

            # Has this runner ran this game before, init the game and category
            if !runner.historic_runs.key?(gameID)
              runner.historic_runs[gameID] = RunnerGame.new(gameID, gameName)
              runner.historic_runs[gameID].categories[category.category_id] = RunnerCategory.new(category.category_id, category.category_name)
            # If the runner has ran the game before, but not the category yet
            elsif !runner.historic_runs[gameID].categories.key?(category.category_id)
              runner.historic_runs[gameID].categories[category.category_id] = RunnerCategory.new(category.category_id, category.category_name)
            end # else its fine

            category.number_submitted_runs += 1
            runner.num_submitted_runs += 1
            runner.total_time_overall += Integer(run['times']['primary_t'])
            runner.historic_runs[gameID].num_submitted_runs += 1
            runner.historic_runs[gameID].total_time_overall += Integer(run['times']['primary_t'])
            runner.historic_runs[gameID].categories[category.category_id].num_submitted_runs += 1
            runner.historic_runs[gameID].categories[category.category_id].total_time_overall += Integer(run['times']['primary_t'])

            # Check if the run is a new milestone for this runner
            runnerCurrentPB = runner.historic_runs[gameID].categories[category.category_id].current_pb_time
            nextMilestone = Util.nextMilestone(runnerCurrentPB)
            if runnerCurrentPB == Util::MaxInteger
              runner.historic_runs[gameID].categories[category.category_id]
                    .milestones['First Run'] = run['weblink']
            elsif nextMilestone >= Integer(run['times']['primary_t'])
              runner.historic_runs[gameID].categories[category.category_id]
                    .milestones[Util.currentMilestoneStr(nextMilestone)] = run['weblink']
            end

            # Update if PB
            if Integer(run['times']['primary_t']) < runner.historic_runs[gameID].categories[category.category_id].current_pb_time
              runner.historic_runs[gameID].categories[category.category_id].current_pb_time = Integer(run['times']['primary_t'])
              runner.historic_runs[gameID].categories[category.category_id].current_pb_id = run['id']
            end

            # Check if new WR
            # TODO:, support ties
            if currentWRTime > Integer(run['times']['primary_t'])

              category.number_submitted_wrs += 1
              runner.num_submitted_wrs += 1
              runner.historic_runs[gameID].num_previous_wrs += 1
              runner.historic_runs[gameID].categories[category.category_id].num_previous_wrs += 1

              # Update state
              currentWRTime = Integer(run['times']['primary_t'])

              runDate = nil
              # If the run has no date, fallback to the verified date
              if !run['date'].nil?
                runDate = Date.strptime(run['date'], '%Y-%m-%d')
              elsif !run['status']['verify-date'].nil?
                runDate = Date.strptime(run['status']['verify-date'].split('T').first, '%Y-%m-%d') # TODO:: cant strp date and time at same time? loses accuracy, fix
              end

              # Before we scrap the old date, see if it's the new longest WR
              if currentWRDate.nil? && !runDate.nil?
                currentWRDate = runDate
              elsif !currentWRDate.nil? && !runDate.nil?
                if (runDate - currentWRDate).to_i > longestHeldWR
                  longestHeldWR = (runDate - currentWRDate).to_i
                  longestHeldWRID = currentWRID
                  category.longest_held_wr_id = currentWRID
                  category.longest_held_wr_time = longestHeldWR
                end
              end

              currentWRID = run['id']
              currentWRDate = runDate
              numSubmittedWRs += 1

              category.current_wr_run_id = currentWRID
              category.current_wr_time = currentWRTime
            end # end WR IF statement

            # Moderator stuff
            if !run['status']['examiner'].nil?
              modKey = run['status']['examiner']
              # If the moderator is no longer a moderator, create them
              unless modList.key?(modKey)
                modList[modKey] = Moderator.new(modKey, SrcAPI.getUserName(modKey))
                modList[modKey].past_moderator = true
              end

              mod = modList[modKey]
              mod.total_verified_runs += 1

              # If there is no verify date, skip it
              if run['status']['verify-date'].nil?
                next
              end
              # If the moderator doesnt have a recent verified run date
              if mod.last_verified_run_date.nil?
                mod.last_verified_run_date = Date.strptime(run['status']['verify-date'].split('T').first, '%Y-%m-%d')
              # If the verified date is more recent (epoch, greater is closer)
              # NOTE dont need time here
              elsif mod.last_verified_run_date < Date.strptime(run['status']['verify-date'].split('T').first, '%Y-%m-%d')
                mod.last_verified_run_date = Date.strptime(run['status']['verify-date'].split('T').first, '%Y-%m-%d')
              end
            end # end of moderator stuff check
          end # end run loop

          # If no more pages to loop through
          break if pagination['links'].length <= 0
          requestLink = SrcAPI.getFwdLink('next', pagination['links'])
          break if requestLink == nil # i dont feel like thinking so another break
        end # end of category's runs loop
      end # end of category loop

      # Update current runners
      SQLiteDB.updateCurrentRunners(currentRunnerList)
      # Insert new runners
      SQLiteDB.insertNewRunners(newRunnerList)

    end # ends seed function
  end # ends seedDB module
end
