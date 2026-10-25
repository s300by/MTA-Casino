# Casino — MTA:SA

A full casino resource for **Multi Theft Auto: San Andreas (MTA:SA)** featuring Blackjack, Poker and a Fortune Wheel / Roulette, with placeable tables, chips, cards and sounds.

**Developer:** Sc00By

---

## Overview

The `casino` resource bundles three games behind a shared core:

| Game | Folder | Description |
|------|--------|-------------|
| Blackjack | `casino/blackjack` | Multi‑seat blackjack with hit/stand/double, dealer AI and payout history. |
| Poker | `casino/poker` | Table poker with small/big blinds, min/max entry and dealer flow. |
| Fortune Wheel | `casino/fortunewheel` | Wheel of fortune / roulette style betting with chips placed on fields. |

Shared models, textures, card images, chips, fonts and sounds live under `casino/files/`.

## Requirements

- MTA:SA server **1.5.7** or newer.
- A MySQL / MariaDB database.
- A server framework exposing money functions. These scripts use OwlGaming‑style exports such as `exports.global:giveMoney` / `takeMoney`.

## Installation

### 1. Create the database tables

Run the following in phpMyAdmin (SQL tab):

```sql
CREATE TABLE `blackjack` (
  `id` int(11) NOT NULL,
  `x` float NOT NULL,
  `y` float NOT NULL,
  `z` float NOT NULL,
  `rz` float NOT NULL,
  `interior` int(11) NOT NULL,
  `dimension` int(11) NOT NULL,
  `minEntry` int(64) NOT NULL,
  `maxEntry` int(64) NOT NULL,
  `credit` bigint(20) NOT NULL DEFAULT 0,
  `creditAll` bigint(20) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_hungarian_ci;

ALTER TABLE `blackjack` ADD PRIMARY KEY (`id`);
ALTER TABLE `blackjack`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

CREATE TABLE `pokertables` (
  `id` int(11) NOT NULL,
  `posX` float NOT NULL,
  `posY` float NOT NULL,
  `posZ` float NOT NULL,
  `rotZ` float NOT NULL,
  `interior` int(11) NOT NULL,
  `dimension` int(11) NOT NULL,
  `smallBlind` bigint(20) NOT NULL,
  `bigBlind` bigint(20) NOT NULL,
  `minEntry` int(64) NOT NULL,
  `maxEntry` int(64) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_hungarian_ci;

ALTER TABLE `pokertables` ADD PRIMARY KEY (`id`);
ALTER TABLE `pokertables`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

CREATE TABLE `fortunewheels` (
  `id` int(11) NOT NULL,
  `x` float NOT NULL,
  `y` float NOT NULL,
  `z` float NOT NULL,
  `rz` float NOT NULL,
  `interior` int(11) NOT NULL,
  `dimension` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_hungarian_ci;

ALTER TABLE `fortunewheels` ADD PRIMARY KEY (`id`);
ALTER TABLE `fortunewheels`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;
```

### 2. Adapt to your framework (non‑OwlGaming servers)

- Change the MySQL connections in `poker/sourceS.lua`, `fortunewheel/sourceS.lua` and `blackjack/sourceS.lua`.
- Replace all `exports.global` money calls (e.g. `giveMoney`, `takeMoney`) with the functions your server uses to take, get, set or give player money.

### 3. Deploy

Drop the `casino` folder into your server's `resources` directory and start it after your database and money resources are running.

## License / Credits

Developed by **Sc00By**. Provided as‑is, without warranty.
