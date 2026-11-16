//! Misure delle scritte del font 8x8: le stesse delle bitmap di tools/gen_attract_assets.py.

use paddws_mister_ui::dl::{letters, text_w};

#[test]
fn larghezze_delle_scritte() {
    assert_eq!(text_w(b"INSERT COIN"), 87);
    assert_eq!(text_w(b"CREDIT "), 56);
    assert_eq!(text_w(b"GAME OVER"), 71);
    assert_eq!(text_w(b"CPU WINS"), 63);
}

#[test]
fn lettere_di_game_over() {
    // game_over_l1 di pong_attract.vh (4.3.0)
    let mut l1 = [0i32; 16];
    let n = letters(b"GAME OVER", None, Some(&mut l1));
    assert_eq!(n, 8);
    assert_eq!(&l1[..8], &[7, 15, 23, 31, 47, 55, 63, 71]);
    assert_eq!(letters(b"P1 WINS", None, None), 6);
    assert_eq!(letters(b"CPU WINS", None, None), 7);
}
