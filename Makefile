#工程的名称及最后生成文件的名字
TARGET = TEST

RM := rm -rf

#打开显示选项
ifneq ($(V),1)
Q		    := @
endif

#优化等级
ifeq ($(OPT),0)
OPTSRC = -O0
else ifeq ($(OPT),1)
OPTSRC = -O1
else ifeq ($(OPT),2)
OPTSRC = -O2
else ifeq ($(OPT),3)
OPTSRC = -O3
else ifeq ($(OPT),s)
OPTSRC = -Os
else 
OPTSRC = -Og
endif


#定义工具链
PREFIX		?= arm-none-eabi
CC		    := $(PREFIX)-gcc
CXX		    := $(PREFIX)-g++
LD		    := $(PREFIX)-gcc
AR		    := $(PREFIX)-ar
AS		    := $(PREFIX)-as
OBJCOPY		:= $(PREFIX)-objcopy
OBJDUMP		:= $(PREFIX)-objdump
SIZE        := $(PREFIX)-size
GDB		    := $(PREFIX)-gdb

#读取当前工作目录
TOP_DIR = .

# 宏定义
DEFS		= -D STM32F10X_HD -D USE_STDPERIPH_DRIVER

#链接脚本
LDSCRIPT    = $(TOP_DIR)/stm32_flash.ld

# 架构相关编译指令
FP_FLAGS	= -msoft-float
ARCH_FLAGS	= -mthumb -mcpu=cortex-m3

# OpenOCD specific variables
OOCD		?= openocd
OOCD_INTERFACE	?= flossjtag
OOCD_TARGET	?= stm32f1x

#设定包含文件目录
INC_DIR= -I $(TOP_DIR)/core           \
         -I $(TOP_DIR)/hardware       \
         -I $(TOP_DIR)/stm32_lib/inc  \
         -I $(TOP_DIR)/system         \
         -I $(TOP_DIR)/user

SOURCE_DIRS = $(TOP_DIR)/core          \
              $(TOP_DIR)/hardware      \
			  $(TOP_DIR)/stm32_lib     \
			  $(TOP_DIR)/stm32_lib/src \
			  $(TOP_DIR)/system        \
			  $(TOP_DIR)/user

DEBUG_DIRS = $(TOP_DIR)/debug
DEBUG_DIRS += $(SOURCE_DIRS:./%=$(TOP_DIR)/debug/%)

CCFLAGS = $(ARCH_FLAGS)
CCFLAGS += $(OPTSRC)
CCFLAGS += -fmessage-length=0 -fsigned-char -ffunction-sections                  \
           -fdata-sections -ffreestanding -fno-move-loop-invariants
CCFLAGS += -Wall -Wextra  -g3
CCFLAGS += $(INC_DIR)
CCFLAGS += $(DEFS)
CCFLAGS += -std=gnu11 -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -c


ASFLAGS = $(ARCH_FLAGS)
ASFLAGS += $(OPTSRC)
ASFLAGS += -fmessage-length=0 -fsigned-char -ffunction-sections                  \
           -fdata-sections -ffreestanding -fno-move-loop-invariants
ASFLAGS += -Wall -Wextra  -g3 -x assembler-with-cpp
ASFLAGS += $(INC_DIR)
ASFLAGS += $(DEFS)
ASFLAGS += -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -c


LDFLAGS = $(ARCH_FLAGS)
LDFLAGS += -specs=nano.specs -specs=nosys.specs -static
LDFLAGS += -Wl,--start-group -lc -lm -Wl,--end-group -Wl,-cref,-u,Reset_Handler -Wl,-Map=$(TARGET).map -Wl,--gc-sections \
           -Wl,--defsym=malloc_getpagesize_P=0x80
LDFLAGS += -T $(LDSCRIPT)


# 展开工作 子目录中的inc文件（inc文件中添加需要编译链接的.c，.s等文件）
-include $(TOP_DIR)/core/make.inc
-include $(TOP_DIR)/hardware/make.inc
-include $(TOP_DIR)/stm32_lib/make.inc
-include $(TOP_DIR)/system/make.inc
-include $(TOP_DIR)/user/make.inc

 
C_OBJS = $(C_SRCS:./%.c=$(TOP_DIR)/debug/%.o)
ASM_OBJS = $(ASM_SRCS:./%.S=$(TOP_DIR)/debug/%.o)
OBJS = $(C_OBJS) 
OBJS += $(ASM_OBJS)
DEPS = $(OBJS:%.o=%.d)

SECONDARY_FLASH = $(TARGET).hex
SECONDARY_SIZE = $(TARGET).siz
SECONDARY_BIN = $(TARGET).bin


.PHONY: images clean elf bin hex list debug stlink-flash style-code flash debug_file


all: $(TARGET).images
	@printf "  building done\n"

elf: $(TARGET).elf
	@printf "  SIZE    $(TARGET).elf\n\n"
	$(Q)$(SIZE) --format=berkeley "$(TARGET).elf"

bin: $(TARGET).bin

hex: $(TARGET).hex

list: $(TARGET).list

flash: $(TARGET).flash

stlink-flash: $(TARGET).stlink-flash

debug: $(TARGET).debug

style-code:
	sh $(TOP_DIR)/buildtool/stylecode.sh

$(TARGET).images: $(TARGET).bin $(TARGET).hex $(TARGET).list $(TARGET).map
	$(Q)printf "  images generated\n"


$(TARGET).elf: $(OBJS) $(LDSCRIPT)
	@printf "  LD      $(TARGET).elf\n"
	$(Q)$(CC) $(LDFLAGS) -o "$(TARGET).elf" $(C_OBJS) $(ASM_OBJS)
	@printf "  SIZE    $(TARGET).elf\n\n"
	$(Q)$(SIZE) --format=berkeley "$(TARGET).elf"
	@printf "\n"


$(TARGET).hex: $(TARGET).elf
	@printf "  OBJCOPY $(TARGET).hex\n"
	$(Q)$(OBJCOPY) $(TARGET).elf  $(TARGET).hex -Oihex


$(TARGET).bin: $(TARGET).elf
	@printf "  OBJCOPY $(TARGET).bin\n"
	$(Q)$(OBJCOPY) $(TARGET).elf  $(TARGET).bin -Obinary

$(TARGET).list: $(TARGET).elf
	@printf "  OBJDUMP $(TARGET).list\n"
	$(Q)$(OBJDUMP) -S $(TARGET).elf > $(TARGET).list


$(C_OBJS):$(TOP_DIR)/debug/%.o:$(TOP_DIR)/%.c 
	@printf "  CC      $<\n"
	$(Q)$(CC) $(CCFLAGS) -o $@ $<

$(ASM_OBJS):$(TOP_DIR)/debug/%.o:$(TOP_DIR)/%.S 
	@printf "  AS      $<\n"
	$(Q)$(CC) $(ASFLAGS) -o $@ $<

debug_file:
	$(Q)-mkdir $(DEBUG_DIRS)

# 使用stlink驱动下载bin程序
$(TARGET).stlink-flash: $(TARGET).bin
	@printf "  ST-link FLASH  $<\n"
	$(Q)$(STFLASH) write $(*).bin 0x8000000

# 使用OpenOCD下载hex程序
$(TARGET).flash: $(TARGET).hex
	@printf "  OPEN_OCD FLASH $<\n"
	$(Q)$(OOCD) $(OOCDFLAGS) -c "program $(*).hex reset verify exit" 

# 使用GDB 通过sdtin/out管道与OpenOCD连接 并在main函数处打断点后运行
$(TARGET).debug: $(TARGET).elf
	@printf "  GDB DEBUG $<\n"
	$(Q)$(GDB) -iex 'target extended | $(OOCD) $(OOCDFLAGS) -c "gdb_port pipe"' \
	-iex 'monitor reset halt' -ex 'load' -ex 'break main' -ex 'c' $(*).elf

-include $(DEPS)

clean:
	@printf "  CLEAN\n"
	$(Q)-$(RM) $(DEPS) $(OBJS) $(TARGET).elf $(TARGET).map $(TARGET).list $(TARGET).bin $(TARGET).hex
