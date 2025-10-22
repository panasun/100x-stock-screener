import Config

config :hound,
  driver: "chrome_driver",
  browser: "chrome",
  port: 9515,
  app_host: "http://localhost",
  app_port: 4000,
  retry_time: 1000,
  screenshot_dir: "screenshots",
  screenshot_on_failure: true 