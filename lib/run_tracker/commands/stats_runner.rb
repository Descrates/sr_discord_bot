module RunTracker
  module CommandLoader
    module StatsRunner
      extend Discordrb::Commands::CommandContainer

      # Bucket for rate limiting. Limits to x uses every y seconds at z intervals.
      bucket :limiter, limit: 1, time_span: 5, delay: 1

      command(:statsrunner, description: 'Displays all or a particular stat for a given runner',
                        usage: "#{PREFIX}statsrunner <runnerName> <game/category> <gameAlias/categoryAlias>",
                        permission_level: PERM_USER,
                        rate_limit_message: 'Command Rate-Limited to Once every 5 seconds!',
                        bucket: :limiter,
                        min_args: 1,
                        max_args: 3) do |_event, _runnerName, _type, _alias|

        # Command Body
        
        # First verify if that runner even exists
        runners = SQLiteDB.getCurrentRunners
        theRunner = nil
        runners.each do |key, runner|
          if runner.src_name.casecmp(_runnerName.downcase).zero? or
            (runner.src_name.casecmp('guest').zero? and runner.src_id.casecmp(_runnerName.downcase).zero?)
            theRunner = runner
          end
        end

        # didnt find it
        if theRunner == nil
          # TODO: add fuzzy search with API to get the id if cant find anything
          _event << "No runner found with that name, try again"
          next
        end

        # else, we can do things with it.
        embed = Discordrb::Webhooks::Embed.new(
          title: "Runner Summary for - #{_runnerName}",
          thumbnail: {
            url: theRunner.avatar_url
          },
          description: "To View Category Information:\n`#{PREFIX}statsrunner #{_runnerName} <categoryAlias>`",
          footer: {
            text: "#{PREFIX}help to view a list of available commands"
          }
        )

        embed.colour = "#1AB5FF"
        # If only the runner name was supplied, print out a summary of the runner
        if _type == nil and _alias == nil
          # Name
          # games have done runs in
          runnersGames = Array.new
          theRunner.historic_runs.each do |key, game|
            runnersGames.push(game.src_name)
          end
          embed.add_field(
            name: "Runs of Games that are Tracked",
            value: runnersGames.join("\n"),
            inline: false
          )
          embed.add_field(
            name: "Number of Submitted Runs",
            value: theRunner.num_submitted_runs,
            inline: true
          )
          embed.add_field(
            name: "Number of Submitted World Records",
            value: theRunner.num_submitted_wrs,
            inline: true
          )
          embed.add_field(
            name: "Total Time Spent Across all runs",
            value: "#{(theRunner.total_time_overall/3600.0).round(2)} hours",
            inline: true
          )
        # If we are only given the game alias
        elsif _type.downcase.casecmp('game').zero? and _alias != nil
          # Check to see if alias even exists
          gameID = SQLiteDB.findID(_alias)
          if gameID == nil
            _event << "Game Alias not found use !listgames to see the current aliases"
            next
          end

          # Check to see if that runner has done runs of that game
          foundGame = nil
          theRunner.historic_runs.each do |key, game|
            if key.casecmp(gameID).zero?
              foundGame = game
            end
          end
          if foundGame == nil
            _event << "That runner has not done a run of that game"
            next
          end

          # categories have done runs in
          runnersCategories = Array.new
          foundGame.categories.each do |key, category|
            if category.num_submitted_runs > 0
              runnersCategories.push(category.src_name)
            end
          end
          embed.title = "Runner Summary for #{_runnerName} in Game #{_alias}"
          embed.add_field(
            name: "Categories that have done Runs in",
            value: runnersCategories.join("\n"),
            inline: false
          )
          embed.add_field(
            name: "Number of Submitted Runs",
            value: foundGame.num_submitted_runs,
            inline: true
          )
          embed.add_field(
            name: "Number of Submitted World Records",
            value: foundGame.num_previous_wrs,
            inline: true
          )
          embed.add_field(
            name: "Total Time Spent Across all runs",
            value: "#{(foundGame.total_time_overall/3600.0).round(2)} hours",
            inline: true
          )
        # Otherwise print category information
        elsif _type.downcase.casecmp('category').zero? and _alias != nil
          # Check to see if alias even exists
          # Check to see if they've done the category
          categoryID = SQLiteDB.findID(_alias)
          if categoryID == nil
            _event << "Category Alias not found use #{PREFIX}listcategories <gameAlias> to see the current aliases"
            next
          end

          gameID = SQLiteDB.categoryAliasToGameID(_alias)

          # Check to see if that runner has done runs of that game
          foundGame = nil
          theRunner.historic_runs.each do |key, game|
            if key.casecmp(gameID).zero?
              foundGame = game
            end
          end
          if foundGame == nil
            _event << "That runner has not done a run of that game"
            next
          end

          # Check to see if that runner has done runs of that category
          category = foundGame.categories[categoryID]
          if category.num_submitted_runs <= 0
            _event << "That runner has not done a run of that category for that category!"
            next
          end

          # Name
          # milestones
          milestoneList = Array.new
          category.milestones.each do |label, runID|
            milestoneList.push("_#{label}_: #{runID}")
          end
          # TODO: add back game name
          embed.title = "Runner Summary for #{_runnerName} in Category #{_alias}"
          embed.add_field(
            name: "Milestones for this Category",
            value: milestoneList.join("\n"),
            inline: false
          )
          embed.add_field(
            name: "Number of Submitted Runs",
            value: category.num_submitted_runs,
            inline: true
          )
          embed.add_field(
            name: "Number of Submitted World Records",
            value: category.num_previous_wrs,
            inline: true
          )
          embed.add_field(
            name: "Total Time Spent Across all runs",
            value: "#{(category.total_time_overall/3600.0).round(2)} hours",
            inline: true
          )
        else
          _event << "#{PREFIX}statsrunner <runnerName> <game/category> <gameAlias/categoryAlias>"
          next
        end
        RTBot.send_message(_event.channel.id, "", false, embed)
      end # end of command body
    end
  end
end
