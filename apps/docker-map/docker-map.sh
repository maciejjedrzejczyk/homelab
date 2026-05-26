#!/bin/bash
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$APP_DIR/.docker-map.pid"
PORT=3009

start() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "Docker Map is already running (PID $(cat "$PID_FILE"))"
    return 1
  fi

  # Check if port is in use
  EXISTING_PID=$(lsof -ti :"$PORT" 2>/dev/null)
  if [ -n "$EXISTING_PID" ]; then
    echo "Port $PORT is already in use by PID $EXISTING_PID"
    printf "Kill it? [y/N] "
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
      kill "$EXISTING_PID" && echo "Killed PID $EXISTING_PID"
      sleep 1
    else
      echo "Aborting."
      return 1
    fi
  fi

  cd "$APP_DIR" && node server.js &
  echo $! > "$PID_FILE"
  echo "Docker Map started (PID $!) at http://localhost:$PORT"
}

stop() {
  if [ ! -f "$PID_FILE" ]; then
    echo "No PID file found. Docker Map may not be running."
    return 1
  fi

  PID=$(cat "$PID_FILE")
  if kill "$PID" 2>/dev/null; then
    echo "Stopped Docker Map (PID $PID)"
  else
    echo "Process $PID not running."
  fi
  rm -f "$PID_FILE"

  # Ensure port is freed
  REMAINING=$(lsof -ti :"$PORT" 2>/dev/null)
  if [ -n "$REMAINING" ]; then
    kill "$REMAINING" 2>/dev/null
  fi
}

case "${1:-}" in
  start) start ;;
  stop)  stop ;;
  restart) stop; sleep 1; start ;;
  *) echo "Usage: $0 {start|stop|restart}" ; exit 1 ;;
esac
