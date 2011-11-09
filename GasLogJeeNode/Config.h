//---------------------------------------------------------------------------------------------------
// RF12 settings
//---------------------------------------------------------------------------------------------------
// fixed RF12 settings

#define myNodeID 10 //in the range 1-30
#define network 210 //default network group (can be in the range 1-250). All nodes required to communicate together must be on the same network group
#define freq RF12_868MHZ //Frequency of RF12B module can be RF12_433MHZ, RF12_868MHZ or RF12_915MHZ. You should use the one matching the module you have.

// set the sync mode to 2 if the fuses are still the Arduino default
// mode 3 (full powerdown) can only be used with 258 CK startup fuses
#define RADIO_SYNC_MODE 2

#define COLLECT 0x20 // collect mode, i.e. pass incoming without sending acks
