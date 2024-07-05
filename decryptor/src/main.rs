use std::{env, process};
use openssl::symm::{decrypt, Cipher};
use hex;

fn decrypt_authinfo(authinfo_raw: String) -> Result<(String, String), String> {
    let authinfo = hex::decode(authinfo_raw).map_err(|_| "Invalid hex encoding for authinfo")?;

    let cipher = Cipher::des_ede3();
    let iv = [0u8; 8];

    // Decrypting loop, iterating from 000000 to 999999
    for i in 0..1_000_000 {
        let key = format!("{:06}", i);
        let key_bytes = format!("{}000000000000000000", key).into_bytes();

        match decrypt(cipher, &key_bytes, Some(&iv), &authinfo) {
            Ok(bytes) => {
                let result = String::from_utf8_lossy(&bytes);

                if result.contains("OTT") {
                    return Ok((key, result.to_string()));
                }
            }
            Err(_) => {
                // Decryption failed with this key, continue trying
            }
        }
    }

    return Err("Could not find a possible key".to_string());
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() != 2 {
        eprintln!("Usage: {} <authinfo>", args[0]);
        process::exit(1);
    }

    let authinfo_raw = args[1].clone();

    match decrypt_authinfo(authinfo_raw) {
        Ok((key, result)) => {
            let components: Vec<&str> = result.split('$').collect();

            println!("========================================");
            println!("Found key: {}", key);
            println!("========================================");
            println!("{}", result);
            println!("========================================");
            println!("      random:  {}", components[0]);
            println!(" encry token:  {}", components[1]);
            println!("     user id:  {}", components[2]);
            println!("   device id:  {}", components[3]);
            println!("  ip address:  {}", components[4]);
            println!(" mac address:  {}", components[5]);
            println!("    reserved:  {}", components[6]);
            println!("         ott:  {}", components[7]);
        }
        Err(err) => {
            eprintln!("Error: {}", err);
        }
    }
}
