# LAB3-22 스텝모터 위상 제어 — 실험 전 보고서

- 설계 top 모듈: `lab3_stepper` (파일: `src/lab3_stepper.v`)
- 테스트벤치 top: `tb_design` (파일: `sim/tb_stepper.sv`)
- 제약 파일: `constraints/lab3_stepper.xdc`
- 대상 보드/파트: Combo II-DLD S75, xc7s75fgga484-1, MAIN CLOCK F = 50 MHz

## 1. 회로 목적

clock-enable(내부에서 만든 분주 펄스)마다 4상 코일 패턴(stepmotor[3:0])을 한 칸씩 이동시켜
스텝모터를 정회전·역회전시키고, `enable=0`일 때는 현재 위상에서 정지시키는 회로다.
최상위 클록은 `clk_50mhz` 하나뿐이며, 느린 스텝 속도는 내부 카운터가 만드는
clock-enable(=카운터가 `STEP_CYCLES-1`에 도달하는 순간)로 구현한다. 방향(`direction`)과
동작 여부(`enable`)는 보드 스위치에서 들어오는 비동기 레벨 입력이므로 2단(FF 2개)
동기화를 거쳐 내부에서 사용한다.

## 2. 블록 흐름

```
clk_50mhz, rst_p
      │
      ▼
[2-FF 동기화]  enable, direction  →  enable_sync, direction_sync
      │
      ▼
[step 카운터]  count: 0 ~ STEP_CYCLES-1
      │  (count == STEP_CYCLES-1 이고 enable_sync=1 일 때)
      ▼
[상태 레지스터] state[1:0]  (direction_sync=1이면 -1, 아니면 +1)
      │
      ▼
[출력 디코더]  state → stepmotor[3:0]  (4상 여자 패턴, combinational case)
```

- enable_sync=0이면 count는 0으로 고정되어 state가 멈춘다 (모터 정지, 마지막 위상 유지).
- state는 2비트로 0~3을 순환하며, direction_sync에 따라 증가(정회전) 또는 감소(역회전)한다.

## 3. 파라미터 계산

- `CLK_HZ` = 50,000,000 (50 MHz, 실제 보드 클록)
- `STEP_HZ` = 100 (실습 기본값, 초당 100 스텝 가정)
- `STEP_CYCLES = CLK_HZ / STEP_HZ = 50,000,000 / 100 = 500,000`
  → 클록 500,000번(= 10 ms)마다 한 스텝씩 위상 이동.
- `COUNT_WIDTH = $clog2(STEP_CYCLES) = $clog2(500000) = 19` bit
  (`STEP_CYCLES < 2`일 때만 1비트로 강제하여 파라미터가 0이 되는 경우를 방지)
- 시뮬레이션에서는 실행 시간을 줄이기 위해 축소 파라미터
  `CLK_HZ=8, STEP_HZ=2` → `STEP_CYCLES = 8/2 = 4`, `COUNT_WIDTH = $clog2(4) = 2` 사용.
  (파라미터만 작을 뿐 RTL 구조와 위상 순서는 실제 보드용과 동일)

## 4. 상태/타이밍 표 — 4상 여자 시퀀스

| state (2'd) | stepmotor[3:0] | 코일 A | 코일 B | 코일 C | 코일 D |
|---|---|---|---|---|---|
| 0 | 0011 | 0 | 0 | 1 | 1 |
| 1 | 0110 | 0 | 1 | 1 | 0 |
| 2 | 1100 | 1 | 1 | 0 | 0 |
| 3 (default) | 1001 | 1 | 0 | 0 | 1 |

- 정회전(`direction_sync=0`): state 0→1→2→3→0→... (좌측으로 1비트씩 회전하는 2상 여자 패턴)
- 역회전(`direction_sync=1`): state 0→3→2→1→0→... (역순)
- 전이 조건: `enable_sync=1` 이고 `count == STEP_CYCLES-1`일 때만 state가 바뀌고 count는 0으로 리셋.
- `enable_sync=0`이면 state는 마지막 값에서 정지(count만 0 유지).

## 5. RTL · TB · XDC 역할 설명

- **`src/lab3_stepper.v` (`lab3_stepper`)**: 합성 대상 RTL. 입력 2단 동기화 always 블록,
  step 카운터 및 state 제어 always 블록, state→stepmotor 조합 디코더(case문)로 구성.
  모든 순차 로직은 `clk_50mhz` 하나만 clock으로 사용하고, 분주된 신호를 다른 always의
  clk로 사용하지 않는다(clock-enable 방식).
- **`sim/tb_stepper.sv` (`tb_stepper`)**: Icarus 전용 자기검사 테스트벤치.
  축소 파라미터(`CLK_HZ=8,STEP_HZ=2`)로 DUT를 인스턴스화하고, reset 해제 → enable 인가 →
  정방향 한 주기(4스텝) → 역방향 두 단계 → `enable=0` 정지 유지까지 자극을 인가하며,
  매 단계 `check_value` task로 `stepmotor`가 기대 패턴과 정확히 일치하는지 `!==` 비교로
  검사한다. 불일치 시 `$fatal`, 각 통과마다 `$display("PASS: ...")`, 종료 시 전체 검사
  개수(`checks`)를 `$display`로 요약하고 `$finish`. `$dumpfile("wave.vcd")`/`$dumpvars`로
  파형을 남기고, 두 번째 `initial` 블록이 `#5000` 뒤 `$fatal`로 타임아웃을 강제해 TB가
  항상 확정적으로 종료되도록 한다.
- **`constraints/lab3_stepper.xdc`**: Vivado/실제 보드용 제약. 모든 top 포트에 `PACKAGE_PIN`과
  `IOSTANDARD LVCMOS33`을 지정하고, `clk_50mhz`에 20.000 ns(50 MHz) `create_clock`을 걸고,
  비동기 레벨 입력(`rst_p, enable, direction`)에는 `set_false_path`를 지정한다.
  Icarus 논리 시뮬레이션에는 XDC가 전혀 관여하지 않는다(핀 배정은 보드 단계에서만 의미가 있음).

## 6. TB 자극 → 기대 결과 표

| 순서 | 자극 | 대기 조건 | 기대 stepmotor | 검사 목적 |
|---|---|---|---|---|
| 1 | reset 해제 (`rst_p=0`) | 클록 2회 후 | 4'b0011 | 리셋 직후 state=0 초기값 |
| 2 | `enable=1` | `state==1` | 4'b0110 | 정회전 1스텝 |
| 3 | (유지) | `state==2` | 4'b1100 | 정회전 2스텝 |
| 4 | (유지) | `state==3` | 4'b1001 | 정회전 3스텝 |
| 5 | (유지) | `state==0` | 4'b0011 | 정회전 한 주기 완료(4상 순환) |
| 6 | `direction=1` | `direction_sync=1` 후 `state==3` | 4'b1001 | 역회전 1단계 |
| 7 | (유지) | `state==2` | 4'b1100 | 역회전 2단계 |
| 8 | `enable=0` | `enable_sync=0` 후 클록 12회(가속된 rate) | 4'b1100 | enable=0 유지 시 마지막 위상에서 정지 |

## 7. Icarus PASS 결과 핵심 로그

```
PASS: stepmotor=0011 (check #1)
PASS: stepmotor=0110 (check #2)
PASS: stepmotor=1100 (check #3)
PASS: stepmotor=1001 (check #4)
PASS: stepmotor=0011 (check #5)
PASS: stepmotor=1001 (check #6)
PASS: stepmotor=1100 (check #7)
PASS: stepmotor=1100 (check #8)
LAB3_STEPPER_PASS checks=8
sim/tb_stepper.sv:56: $finish called at 831000 (1ps)
```

`python3 tools/fpga_lab.py simulate` 실행 결과 `build/sim/result.json`의
`"status": "SIMULATED"`를 확인했고, `build/sim/wave.vcd`가 정상 생성됨을 확인했다.

## 8. 한 항목 수정 실험과 복구 결과

정상 상태를 먼저 확인한 뒤, `src/lab3_stepper.v`의 위상 디코더에서 `state==2'd1`(정회전 첫 스텝)의
출력값 한 항목만 의도적으로 오염시켰다: `4'b0110` → `4'b0101` (인접하지 않은 코일 2개가 동시에
켜지는 잘못된 패턴).

| 단계 | 조작 | 결과 |
|---|---|---|
| 정상값 확인 | 원본 그대로 시뮬레이션 | `LAB3_STEPPER_PASS checks=8`, 8개 모두 PASS |
| 고의 오류 삽입 | `2'd1: stepmotor = 4'b0110;` → `4'b0101;` | check #2에서 `$fatal` 발생:<br>`got 0101 expected 0110`<br>`Time: 151000` — 종료 코드 1 (컴파일은 성공, 실행이 실패) |
| 복구 | `4'b0101` → `4'b0110` (원본으로 되돌림) | 재실행 시 다시 `LAB3_STEPPER_PASS checks=8`, 8개 모두 PASS, `$finish` 정상 호출 (종료 코드 0) |

TB의 기대값(`check_value` 호출부)은 전혀 수정하지 않고 RTL만 되돌려 PASS가 복구됨을 확인했다.
이는 자기검사 TB가 실제로 위상 시퀀스의 오류를 정확히 검출한다는 것을 보여준다.

## 9. 실제 보드 확인 체크리스트

- [ ] 보드 전원을 끈 상태에서 스텝모터 드라이버 모듈과 FPGA 사이의 외부 배선, 공통 GND를
      먼저 확인한다. **FPGA 핀에서 모터를 직접 구동하지 않고, 별도의 모터 드라이버와
      별도 전원(모터 전용 전원 레일)을 사용한다.** LVCMOS33 신호는 드라이버 입력단까지만
      연결한다.
- [ ] `create_project` 시 Part를 `xc7s75fgga484-1`로 정확히 선택했는지 확인.
- [ ] `constraints/lab3_stepper.xdc`의 `PACKAGE_PIN`이 top module(`lab3_stepper`) 포트명과 대소문자까지
      정확히 일치하는지 Open Elaborated Design / I/O Planning에서 대조.
- [ ] Reports → Timing → Report Clocks에서 `clk_50mhz` 주기 20.000 ns 확인.
- [ ] Synthesis → Implementation → Generate Bitstream까지 오류 없이 완료했는지 확인.
- [ ] Hardware Manager → Open Target → Auto Connect → Program Device로 bit 파일을 로드하고
      생성 시각을 기록.
- [ ] 드라이버 결선 후: 정회전/역회전 방향 스위치 동작, 스텝 속도, `enable=0` 정지 유지가
      의도대로 동작하는지 관찰. 모터 발열 여부도 함께 관찰(과열 시 즉시 전원 차단).
- [ ] 보드 전체 사진과 사용한 핀 위치가 보이는 사진, 입력 조작과 출력 변화가 함께 보이는
      동작 영상을 확보한다.
- [ ] GitHub 저장소에 `src/sim/constraints/simulation.json`만 최종본으로 관리하고 빌드
      생성물(`build/` 등)은 제외한 뒤 커밋 해시를 기록한다.

## 10. 핀 표 요약

| 신호명 (RTL 포트) | PACKAGE_PIN | IOSTANDARD |
|---|---|---|
| clk_50mhz | B6 | LVCMOS33 |
| rst_p | K4 | LVCMOS33 |
| enable | N8 | LVCMOS33 |
| direction | N4 | LVCMOS33 |
| stepmotor[3] | Y20 | LVCMOS33 |
| stepmotor[2] | Y22 | LVCMOS33 |
| stepmotor[1] | AA20 | LVCMOS33 |
| stepmotor[0] | AA21 | LVCMOS33 |

추가 타이밍/경로 제약: `create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]`,
`set_false_path -from [get_ports {rst_p enable direction}]` (비동기 레벨 입력이므로 정적
타이밍 분석에서 제외).
