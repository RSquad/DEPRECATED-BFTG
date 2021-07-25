pragma ton-solidity >=0.37.0;

library Errors {
    uint16 constant ONLY_CONTRACT = 1001;
    uint16 constant ONLY_STORE = 1002;
    uint16 constant ONLY_SIGNED = 1003;

    uint16 constant STORE_UNDEFINED = 2001;

    uint16 constant ID_ALREADY_TAKEN =                  102;
    uint16 constant ONLY_DEPLOYER =                     103;
    uint16 constant NOT_AUTHORIZED_CONTRACT =           104;
    uint32 constant ACCOUNT_DOES_NOT_EXIST =            105;
    uint32 constant MSG_VALUE_TOO_LOW =                 106;

    uint32 constant STORE_SHOULD_BE_NOT_NULL =          201;
    
    uint16 constant PADAWAN_ALREADY_DEPLOYED =          301;
    uint16 constant PROPOSAL_ALREADY_DEPLOYED =         302;
    uint16 constant NOT_ALL_CHECKS_PASSED =             303;
    uint16 constant INIT_ALREADY_COMPLETED =            304;
    uint16 constant END_LOWER_THAT_START =              305;
    uint16 constant NOW_LOWER_THAT_START =              306;
    uint16 constant BAD_DATES =                         307;

    uint16 constant VOTING_NOT_STARTED =                401;
    uint16 constant VOTING_HAS_ENDED =                  402;
    uint16 constant VOTING_HAS_NOT_ENDED =              403;

    uint32 constant NOT_ENOUGH_VOTES =                  500;
    uint32 constant INVALID_CALLER =                    501;
    uint32 constant DEPOSIT_NOT_FOUND =                 502;
    uint32 constant DEPOSIT_WITH_SUCH_ID_EXISTS =       503;
    uint32 constant PENDING_DEPOSIT_ALREADY_EXISTS =    504;
    uint32 constant NOT_ENOUGH_VALUE_TO_VOTE =          505;
}