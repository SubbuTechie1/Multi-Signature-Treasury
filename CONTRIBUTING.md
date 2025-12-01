# Contributing to Multi-Signature Treasury

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Development Setup

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/Multi-Signature-Treasury.git`
3. Install dependencies:
   ```powershell
   cd backend; npm install
   cd ../frontend; npm install
   ```
4. Create a branch: `git checkout -b feature/your-feature-name`

## Code Style

### Move Contracts
- Follow [Sui Move Style Guide](https://docs.sui.io/build/move)
- Use descriptive function and variable names
- Add comprehensive comments for public functions
- Include error codes with descriptive constants

### TypeScript/JavaScript
- Use ESLint for linting
- Follow Airbnb style guide
- Use TypeScript strict mode
- Add JSDoc comments for exported functions

### React
- Use functional components with hooks
- Implement proper error boundaries
- Follow React best practices

## Testing

### Before Submitting

1. Run Move tests:
   ```powershell
   cd contracts
   sui move test
   ```

2. Run backend tests:
   ```powershell
   cd backend
   npm test
   ```

3. Run frontend tests:
   ```powershell
   cd frontend
   npm test
   ```

4. Check linting:
   ```powershell
   npm run lint
   ```

### Test Coverage

- Maintain >80% test coverage for Move contracts
- Add integration tests for new API endpoints
- Include unit tests for utility functions

## Pull Request Process

1. Update README.md with details of changes if needed
2. Update DEPLOYMENT.md if deployment process changes
3. Ensure all tests pass
4. Update documentation and comments
5. Create a pull request with:
   - Clear title describing the change
   - Detailed description of what and why
   - Screenshots for UI changes
   - Link to related issues

## Commit Messages

Follow conventional commits:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `test:` Test additions or modifications
- `refactor:` Code refactoring
- `chore:` Maintenance tasks

Example:
```
feat: add spending limit policy validation

- Implement daily/weekly/monthly limit checks
- Add policy violation events
- Update tests for new validation logic
```

## Feature Requests and Bug Reports

### Bug Reports Should Include:

- Clear description of the issue
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable
- Environment details (OS, Node version, etc.)

### Feature Requests Should Include:

- Use case description
- Proposed solution
- Alternative solutions considered
- Impact on existing functionality

## Code Review

All submissions require review. We use GitHub pull requests for this purpose.

Reviewers will check:
- Code quality and style
- Test coverage
- Documentation updates
- Security implications
- Gas optimization (for Move contracts)

## Community Guidelines

- Be respectful and constructive
- Welcome newcomers and help them get started
- Focus on the code, not the person
- Provide actionable feedback

## Questions?

Feel free to:
- Open an issue for discussion
- Ask in pull request comments
- Reach out to maintainers

Thank you for contributing to Multi-Signature Treasury! 🎉
