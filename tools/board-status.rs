//! 诊断工具：通过 USB HID 向 EasyInput 板子索取运行状态 JSON。
//! 协议见 firmware/components/keyboard/include/keyboard/status_hid_protocol.h

use std::time::{Duration, Instant};

use hidapi::HidApi;

const VID: u16 = 0x303A;
const PID: u16 = 0x1006;
const REQ_REPORT_ID: u8 = 0x13;
const RESP_REPORT_ID: u8 = 0x11;
const CMD_KIND: u8 = 0x04;
const HEADER_LEN: usize = 4;
const META_LEN: usize = 9;

fn crc16_ccitt(data: &[u8]) -> u16 {
    let mut crc: u16 = 0xFFFF;
    for byte in data {
        crc ^= (*byte as u16) << 8;
        for _ in 0..8 {
            crc = if crc & 0x8000 != 0 {
                (crc << 1) ^ 0x1021
            } else {
                crc << 1
            };
        }
    }
    crc
}

fn build_request(request_id: u32, flags: u8) -> Vec<u8> {
    let mut report = vec![0_u8; 17];
    report[0] = REQ_REPORT_ID;
    report[1] = b'S';
    report[2] = b'3';
    report[3] = b'R';
    report[4] = 1;
    report[5..9].copy_from_slice(&request_id.to_le_bytes());
    report[9] = flags;
    report
}

fn main() {
    let api = match HidApi::new() {
        Ok(api) => api,
        Err(error) => {
            eprintln!("hidapi 初始化失败: {error}");
            std::process::exit(1);
        }
    };
    api.set_open_exclusive(false);

    let candidates: Vec<_> = api
        .device_list()
        .filter(|device| device.vendor_id() == VID && device.product_id() == PID)
        .collect();
    if candidates.is_empty() {
        eprintln!("未找到 EasyInput HID 设备");
        std::process::exit(1);
    }
    println!("发现 {} 个 HID 接口", candidates.len());

    let request_id: u32 = 0xA1B2C3D4;
    for (index, candidate) in candidates.iter().enumerate() {
        let device = match candidate.open_device(&api) {
            Ok(device) => device,
            Err(error) => {
                println!("  [{index}] 打不开: {error}");
                continue;
            }
        };
        let usage = candidate.usage_page();
        // flags 必须为 0：Fresh(0x01) 会强制返回简版确认视图，拿不到 audio 段
        if device
            .send_feature_report(&build_request(request_id, 0x00))
            .is_err()
        {
            println!("  [{index}] usage_page={usage:#06x} 发送请求失败");
            continue;
        }

        let mut chunks: std::collections::BTreeMap<u8, Vec<u8>> =
            std::collections::BTreeMap::new();
        let mut total_chunks: Option<u8> = None;
        let mut json_len: usize = 0;
        let mut expected_crc: u16 = 0;
        let deadline = Instant::now() + Duration::from_secs(5);
        let mut buffer = [0_u8; 64];

        while Instant::now() < deadline {
            let Ok(count) = device.read_timeout(&mut buffer, 400) else {
                continue;
            };
            if count < 1 || buffer[0] != RESP_REPORT_ID {
                continue;
            }
            let payload = &buffer[1..count];
            if payload.len() < HEADER_LEN + META_LEN || payload[0] != CMD_KIND {
                continue;
            }
            let chunk_index = payload[1];
            let declared_total = payload[2];
            let declared_len = payload[3] as usize;
            let rid = u32::from_le_bytes(payload[5..9].try_into().unwrap());
            if rid != request_id {
                continue;
            }
            json_len = u16::from_le_bytes(payload[9..11].try_into().unwrap()) as usize;
            expected_crc = u16::from_le_bytes(payload[11..13].try_into().unwrap());
            let chunk_len = declared_len.saturating_sub(META_LEN);
            chunks.insert(
                chunk_index,
                payload[HEADER_LEN + META_LEN..HEADER_LEN + META_LEN + chunk_len].to_vec(),
            );
            total_chunks = Some(declared_total);
            if chunks.len() >= declared_total as usize {
                break;
            }
        }

        let Some(total) = total_chunks else {
            println!("  [{index}] usage_page={usage:#06x} 无响应");
            continue;
        };
        if chunks.len() < total as usize {
            println!(
                "  [{index}] usage_page={usage:#06x} 响应不全 {}/{}",
                chunks.len(),
                total
            );
            continue;
        }

        let mut blob = Vec::new();
        for chunk_index in 0..total {
            if let Some(chunk) = chunks.get(&chunk_index) {
                blob.extend_from_slice(chunk);
            }
        }
        blob.truncate(json_len);
        let crc_ok = crc16_ccitt(&blob) == expected_crc;
        println!(
            "\n=== 接口 {index} 返回状态（CRC {}）===\n",
            if crc_ok { "OK" } else { "不符" }
        );
        match String::from_utf8(blob) {
            Ok(text) => match serde_json::from_str::<serde_json::Value>(&text) {
                Ok(value) => {
                    println!("{}", serde_json::to_string_pretty(&value).unwrap_or(text))
                }
                Err(_) => println!("{text}"),
            },
            Err(error) => println!("非 UTF-8: {error}"),
        }
        return;
    }
    eprintln!("所有接口都没返回状态");
    std::process::exit(1);
}
