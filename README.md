# ruby-sandbox

[![lint](https://github.com/GrantBirki/ruby-sandbox/actions/workflows/lint.yml/badge.svg)](https://github.com/GrantBirki/ruby-sandbox/actions/workflows/lint.yml)

A sandbox for doing things in Ruby

## Setup 🛠

As always, simply run `script/bootstrap` to get started.

## Usage 💻

### Simple Sinatra App

To start the simple Sinatra app, run the following command:

```bash
script/server
```

### Running an Example

The `examples/` directory contains a number of Ruby scripts/examples that you can run. Here is an example:

```bash
# in one terminal window
script/server

# in another terminal window
LOG_LEVEL=DEBUG bundle exec ruby examples/persistent_http_client.rb
```
