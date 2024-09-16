# Do everything.
all: init link defaults brew

# Set initial preference.
init:
	@echo "\033[0;34mRun init.sh\033[0m"
	@scripts/init.sh
	@echo "\033[0;32mDone.\033[0m"

# Link dotfiles.
link:
	@echo "\033[0;34mRun link.sh\033[0m"
	@scripts/link.sh
	@echo "\033[0;32mDone.\033[0m"

# Set macOS system preferences.
defaults:
	@echo "\033[0;34mRun defaults.sh\033[0m"
	@scripts/defaults.sh
	@echo "\033[0;32mDone.\033[0m"

# Install macOS applications.
brew:
	@echo "\033[0;34mRun brew.sh\033[0m"
	@scripts/brew.sh
	@echo "\033[0;32mDone.\033[0m"

update:
	@echo "\033[0;34mRun update.sh\033[0m"
	@scripts/update.sh
	@echo "\033[0;32mDone.\033[0m"
