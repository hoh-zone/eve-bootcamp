import { Box, Flex, Heading, Button, Text, Card } from "@radix-ui/themes";
import { abbreviateAddress, useConnection } from "@evefrontier/dapp-kit";
import { useCurrentAccount, useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

function App() {
  const { handleConnect, handleDisconnect } = useConnection();
  const { signAndExecuteTransaction } = useDAppKit();
  const account = useCurrentAccount();

  const handleAction = async () => {
    const tx = new Transaction();
    // Dummy transaction representing the smart contract call for Example 2
    tx.moveCall({
      target: `0x123::example_02::buy_permit`,
      arguments: [],
    });
    
    try {
      await signAndExecuteTransaction({ transaction: tx });
      alert("Transaction successful!");
    } catch (e) {
      console.log("Transaction failed or cancelled", e);
    }
  };

  return (
    <Box style={{ padding: "20px", maxWidth: "800px", margin: "0 auto" }}>
      <Flex justify="between" align="center" mb="6">
        <Heading>Example 2: 星门收费站 (JumpPermit)</Heading>
        <Button 
          size="3" 
          variant="soft" 
          onClick={() => account?.address ? handleDisconnect() : handleConnect()}
        >
          {account ? abbreviateAddress(account?.address) : "Connect EVE Vault"}
        </Button>
      </Flex>
      
      {account ? (
        <Card size="4" style={{ marginTop: "20px" }}>
          <Heading size="4" mb="4">Smart Contract Interaction</Heading>
          <Text as="p" mb="4" color="gray">
            This dApp provides a frontend interface for the 星门收费站 (JumpPermit) mechanics.
          </Text>
          <Button size="3" onClick={handleAction}>
            Purchase Jump Permit
          </Button>
        </Card>
      ) : (
        <Card size="4" style={{ marginTop: "20px", textAlign: "center" }}>
          <Text as="p">Please connect your EVE Vault wallet to interact with this dApp.</Text>
        </Card>
      )}
    </Box>
  );
}

export default App;
