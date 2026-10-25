#!/usr/bin/env bash
# Halka acik XAUUSD 1 dakikalik veri setlerini indirir (research/data altina).
set -e
cd "$(dirname "$0")"
mkdir -p data && cd data
[ -d gdf ] || git clone --depth 1 https://github.com/getdata-finance/xauusd-1m-ohlcv-metals-historical-data.git gdf
[ -d parshant ] || git clone --depth 1 https://github.com/parshant65-lang/Gold-XAUUSD-1m-2020-2025-Historical-Data.git parshant
