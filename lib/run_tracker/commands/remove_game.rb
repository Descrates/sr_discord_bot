module RunTracker
  module CommandLoader
    module RemoveGame
      extend Discordrb::Commands::CommandContainer

      # Bucket for rate limiting. Limits to x uses every y seconds at z intervals.
      bucket :limiter, limit: 1, time_span: 5, delay: 1

      command(:removegame, description: 'Removes a game from the list of tracked games.',
                           usage: '!removegame <game-alias>',
                           permission_level: PERM_ADMIN,
                           rate_limit_message: 'Command Rate-Limited to Once every 5 seconds!',
                           bucket: :limiter,
                           min_args: 1,
                           max_args: 1) do |_event, _gameAlias|

        # Check to see if the game is even tracked
        gameID = PostgresDB.findID(_gameAlias)
        if gameID == nil
          _event << "That game is not currently being tracked"
          next
        end

        begin

          PostgresDB::Conn.transaction do |conn|

            # Delete the tracked game row
            conn.exec("DELETE from public.tracked_games where game_id = '#{gameID}'")

            # Go through all of the runners and delete the tracked game
            runners = PostgresDB.getCurrentRunners
            runners.each do |key, runner|
              # If the runner hasnt played that game, forget about it
              if !runner.historic_runs.key?(gameID)
                next
              end
              # Else we have to get the stats so we can correct those as well
              game = runner.historic_runs[gameID]
              runner.num_submitted_wrs -= game.num_previous_wrs
              runner.num_submitted_runs -= game.num_submitted_runs
              runner.total_time_overall -= game.total_time_overall
              # Now delete the game
              runner.historic_runs.delete(gameID)
            end
            # Update their fields
            PostgresDB.updateCurrentRunners(runners)

            # Delete the game and category aliases
            conn.exec("DELETE from public.aliases where alias LIKE '#{_gameAlias}%'")

            # Delete the game's resources
            conn.exec("DELETE from public.resources where game_alias = '#{_gameAlias}'")
          end # end of transaction

        rescue Exception => e
          puts "[ERROR] #{e.message} #{e.backtrace}"
          _event << "Error while deleteing the game."
          next
        end # end of begin

        _event << "Game removed successfully"

      end # end of command body

    end
  end
end
