# Contributing

Thanks for helping improve My Signer.

1. Open an issue before starting a large change.
2. Fork the repository and create a focused branch from `main`.
3. Do not use real signing material, tokens, customer data, or production infrastructure in fixtures or documentation.
4. Run the checks below before opening a pull request.

```bash
bundle install
bin/rails db:test:prepare
bundle exec rspec
bundle exec rails test
bin/rubocop
bin/brakeman --no-pager
bundle exec bundle-audit check --update
bin/importmap audit
```

Pull requests should explain the behavior change, include tests, and call out migrations or deployment considerations. By submitting a contribution, you agree that it is licensed under Apache-2.0.
