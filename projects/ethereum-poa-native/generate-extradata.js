/**
 * To encode the signer addresses in extradata, concatenate 32 zero bytes, all signer addresses and 65 further zero bytes. 
 * The result of this concatenation is then used as the value accompanying the extradata key in genesis.json.
 */
const CONCAT_ZERO_PADDING_BYTES = 32
const FURTHER_ZERO_PADDING_BYTES = 65
const NIBBLE = 2;

const address = [process.env.MINER_ADDRESS]
const signers = address.reduce((acc,cur) => acc + (cur.startsWith("0x") ? cur.substring(2) : cur ),"")
const extradata = "0x" + '0'.repeat(CONCAT_ZERO_PADDING_BYTES*NIBBLE) + signers + '0'.repeat(FURTHER_ZERO_PADDING_BYTES*NIBBLE)
console.log(extradata);