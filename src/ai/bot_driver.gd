class_name BotDriver
extends AutopilotDriver
## Host-owned bot (story 002): follows the centerline exactly like the autopilot. Kept as its
## own class so story 005 (tougher bots) can replace the behavior without touching the
## autopilot debug aid. Bots race through KartSim like any kart, so they obey the same rules.
