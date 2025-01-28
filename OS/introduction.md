```c+++`

<!-- test.cpp -->

#include<bits/stdc++.h>
using namespace std;

int main () {
    string str;

    cin>>word;

    cout << << endl;
}


<!-- -S: This option tells gcc to compile the source code i.e. a.cpp into assembly code. It does not produce an executable (.exe) or (.dll), but an assembly source file instead  -->

<!-- -o test.s: This option specifies the output file name for the assembly code, i.e. here test.s -->

<!-- test.c : This is the source file to be compiled -->


g++ -S -o test.s test.cpp 

<!-- so above code will product test.s (assembly) test.o (executable) -->


<!-- test.s: This will be assembly code which is what will be run by the computer (and there are few more steps between where assembly code take by computer to run but that internal detail could be skipped for now) -->

<!-- Assembly code off course is an optimized output for performance so of course it won't human readable friednly but it could be learnt and understood knowing assembly language off course -->


<!-- 

Given the source code i.e. test.cpp

1. pre-processors that happens you have this hash deines hash includes all these things right so that is a pre-processing step then after you have all these things added you have compilation step so that generates assembly code i.e. test.s 

2. Then there is assembler that takes assembly level code and makes it into a binary executable machine code but machine binary bits that computes can understand and then there is certain linking that happens based on where you are running your computer and stuff there are certain linking that that happens 

The generated test.o is the executable file i.e. run by machine

Assembly code (still human readable) -> then it gets converted into machine level code will look like below 

This instruction stream could be looking like a hexadecimal stream: 
B8 22 11 00 FF 01 CA 31 F6 53 8B 5C 24 04 8D 34 48 39 C3 72 EB C3

so, this is the machine bytecode that will be generated from assembly-level code

once again, assembly-level code gets converted to machine-level code which is run by CPU/computer/host machine. 

# Why actually os needed ?

Yes, a program or programming language is just instructions to the hardware. But,
a machine/computer does much more than that, network managment, memory management, storage manamgement, and other things - To handle it all, a central service/software needed that will instruct the hardrware and also keep invidual instructions separated e.g. playing music at the same onlint time downloading a file, running a piece of code, rendering a 3D model etc -> so, with the central service/software i.e. OS each instruction will be handled correctly and separtely without entangling into each other.


-- There is a written piece of code -> assembly-level code -> machine-level code -> OS takes it 

When user press ctrl + s or cmd + s -> the file usually be saved in HDD -> 

If needed, like embedded programming or someone could technically programm without an OS as long programmer can verify the input and output


But OS needed to handle multiple programs / instructions, i.e. main reason

So, yeah OS is like a manager to to manage instructions

 -->


``