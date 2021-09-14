# Free TON BFTG by RSquad

## Testing

To run tests on a local node you need:

- Ubuntu 20.04 or Mac
- install `docker`
- install `node.js`
- install `tondev` using `npm i -g tondev`
- run `Node SE` using `tondev se start`
- clone the repo `git clone --recursive git@github.com:RSquad/BFTG.git`
- don't forget about submodules, if you have cloned withut recursive use `git submodule update --init` to load submodules
- install dependencies at the root of project `npm i`
- run `npm run compile` to compile sources
- create `.env` file, which consists of next variables (for Node SE use the same that provided in example)

```
NETWORK=LOCAL

MULTISIG_ADDRESS=0:d5f5cfc4b52d2eb1bd9d3a8e51707872c7ce0c174facddd0e06ae5ffd17d2fcd
MULTISIG_PUBKEY=99c84f920c299b5d80e4fcce2d2054b05466ec9df19532a688c10eb6dd8d6b33
MULTISIG_SECRET=73b60dc6a5b1d30a56a81ea85e0e453f6957dbfbeefb57325ca9f7be96d3fe1a
```

- run `npm run test` to run tests

_We highly recommended to use `yarn` instead of `npm`_

## Project structure

```
├── build
├── src
│   ├── debots
│   │   └── ...
│   ├── interfaces
│   │   └── ...
│   ├── resolvers
│   │   └── ...
│   └── ...
├── tests
│   └── ...
├── ton-packages
│   └── ...
├── utils
│   └── ...
├── compile.js
├── LICENSE
├── package.json
├── README.md
└── yarn.lock
```

- _./build_ - directory where all compiled contracts are stored
- _./src_ - directory with source code of contracts
- _./src/debots_ - directory containing interfaces for debots
- _./src/interfaces_ - directory containing system contract interfaces
- _./src/resolvers_ - directory containing contracts for inheritance allowing to read addresses and states of other contracts
- _./tests_
- _./ton-packages_
- _./utils_
- _./compile.js_ - file describing the compilation. If you need to compile a new contract, pay attention to the last array of strings, it lists the contracts that will be compiled into ton-package

## License

BFTG is [Apache-2.0 licensed](http://www.apache.org/licenses/LICENSE-2.0 'Apache-2.0 licensed')
