module chapter_14::snippet_01;

// 最简单的 NFT
public struct Badge has key, store {
    id: UID,
    name: vector<u8>,
    description: vector<u8>,
    image_url: vector<u8>,
}
