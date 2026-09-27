`timescale 1ns/1ps
module tb_stepper;
    reg clk_50mhz=0,rst_p=1,enable=0,direction=0;
    wire [3:0] stepmotor;
    integer checks=0;
    always #10 clk_50mhz=~clk_50mhz;
    lab3_stepper #(.CLK_HZ(8),.STEP_HZ(2)) dut
        (.clk_50mhz(clk_50mhz),.rst_p(rst_p),.enable(enable),.direction(direction),.stepmotor(stepmotor));

    task check_value(input [3:0] value); begin
        #1;
        if (stepmotor !== value) $fatal(1, "got %b expected %b", stepmotor, value);
        checks = checks + 1;
        $display("PASS: stepmotor=%b (check #%0d)", stepmotor, checks);
    end endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_stepper);

        // 리셋 해제 직후: state=0 -> 0011
        repeat (2) @(posedge clk_50mhz);
        rst_p = 0;
        check_value(4'b0011);

        // 정방향 한 주기: state 0->1->2->3->0, stepmotor 0011->0110->1100->1001->0011
        enable = 1;
        wait (dut.state == 1);
        check_value(4'b0110);

        wait (dut.state == 2);
        check_value(4'b1100);

        wait (dut.state == 3);
        check_value(4'b1001);

        wait (dut.state == 0);
        check_value(4'b0011);

        // 역방향 두 단계: state 0->3->2, stepmotor 0011->1001->1100
        direction = 1;
        wait (dut.direction_sync);
        wait (dut.state == 3);
        check_value(4'b1001);

        wait (dut.state == 2);
        check_value(4'b1100);

        // enable=0 유지 조건: 가속된 step rate로도 출력이 마지막 위상에서 정지 유지되는지 검사
        enable = 0;
        wait (!dut.enable_sync);
        repeat (12) @(posedge clk_50mhz);
        check_value(4'b1100);

        $display("LAB3_STEPPER_PASS checks=%0d", checks);
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "timeout");
    end
endmodule
