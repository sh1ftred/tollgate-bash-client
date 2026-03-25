# Auto-Pay Internet

Automatic internet payment script using Cashu tokens via cocod.

## Setup

1. Run the initial setup script: `./initial_setup.sh`
2. Install [bun](https://bun.sh)
2. Install [cocod](https://github.com/Egge21M/cocod)
3. Fund your cocod wallet with sats

## Usage

```bash
./auto-pay.sh
```

## How it works

- Starts tracking your network usage
- When data drops below 2 MB, pays 1 sat via Cashu token
- Uses offline tokens first, refills from cocod automatically
- Maintains a stash of 7 offline tokens
- Checks usage every 2s below 10 MB, every 5s above

## Files

- `offline_cashu.txt` - stores offline tokens (auto-created)
