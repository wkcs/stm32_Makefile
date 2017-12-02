#include "sys.h"
#include "usart.h"	  
#include <locale.h>

/*
 * To implement the STDIO functions you need to create
 * the _read and _write functions and hook them to the
 * USART you are using. This example also has a buffered
 * read function for basic line editing.
 */
int _write(int fd, char *ptr, int len);
int _read(int fd, char *ptr, int len);
void get_buffered_line(void);

/*
 * This is a pretty classic ring buffer for characters
 */
#define BUFLEN 127

static uint16_t start_ndx;
static uint16_t end_ndx;
static char buf[BUFLEN + 1];
#define buf_len ((end_ndx - start_ndx) % BUFLEN)
static inline int inc_ndx(int n) { return ((n + 1) % BUFLEN); }
static inline int dec_ndx(int n) { return (((n + BUFLEN) - 1) % BUFLEN); }

static void usart_send_blocking(USART_TypeDef* USARTx, u8 buf) {
    USART_SendData(USARTx, buf);
	while(USART_GetFlagStatus(USARTx,USART_FLAG_TC)!=SET);
}

static u8 usart_recv_blocking(USART_TypeDef* USARTx) {
    return USART_ReceiveData(USARTx);
}

/* back up the cursor one space */
static inline void back_up(void)
{
    end_ndx = dec_ndx(end_ndx);
    usart_send_blocking(USART1, '\010');
    usart_send_blocking(USART1, ' ');
    usart_send_blocking(USART1, '\010');
}

/*
 * A buffered line editing function.
 */
void get_buffered_line(void)
{
    char c;

    if (start_ndx != end_ndx)
    {
        return;
    }

    while (1)
    {
        c = usart_recv_blocking(USART1);

        if (c == '\r')
        {
            buf[end_ndx] = '\n';
            end_ndx = inc_ndx(end_ndx);
            buf[end_ndx] = '\0';
            usart_send_blocking(USART1, '\r');
            usart_send_blocking(USART1, '\n');
            return;
        }

        /* or DEL erase a character */
        if ((c == '\010') || (c == '\177'))
        {
            if (buf_len == 0)
            {
                usart_send_blocking(USART1, '\a');
            }

            else
            {
                back_up();
            }

            /* erases a word */
        }

        else if (c == 0x17)
        {
            while ((buf_len > 0) &&
                    (!(isspace((int) buf[end_ndx]))))
            {
                back_up();
            }

            /* erases the line */
        }

        else if (c == 0x15)
        {
            while (buf_len > 0)
            {
                back_up();
            }

            /* Non-editing character so insert it */
        }

        else
        {
            if (buf_len == (BUFLEN - 1))
            {
                usart_send_blocking(USART1, '\a');
            }

            else
            {
                buf[end_ndx] = c;
                end_ndx = inc_ndx(end_ndx);
                usart_send_blocking(USART1, c);
            }
        }
    }
}

/*
 * Called by libc stdio fwrite functions
 */
int _write(int fd, char *ptr, int len)
{
    int i = 0;

    /*
     * write "len" of char from "ptr" to file id "fd"
     * Return number of char written.
     *
    * Only work for STDOUT, STDIN, and STDERR
     */
    if (fd > 2)
    {
        return -1;
    }

    while (*ptr && (i < len))
    {
        usart_send_blocking(USART1, *ptr);

        if (*ptr == '\n')
        {
            usart_send_blocking(USART1, '\r');
        }

        i++;
        ptr++;
    }

    return i;
}

/*
 * Called by the libc stdio fread fucntions
 *
 * Implements a buffered read with line editing.
 */
int _read(int fd, char *ptr, int len)
{
    int my_len;

    if (fd > 2)
    {
        return -1;
    }

    get_buffered_line();
    my_len = 0;

    while ((buf_len > 0) && (len > 0))
    {
        *ptr++ = buf[start_ndx];
        start_ndx = inc_ndx(start_ndx);
        my_len++;
        len--;
    }

    return my_len; /* return the length we got */
}

 
#if EN_USART1_RX   //如果使能了接收
//串口1中断服务程序
//注意,读取USARTx->SR能避免莫名其妙的错误   	
u8 USART_RX_BUF[USART_REC_LEN];     //接收缓冲,最大USART_REC_LEN个字节.
//接收状态
//bit15，	接收完成标志
//bit14，	接收到0x0d
//bit13~0，	接收到的有效字节数目
u16 USART_RX_STA=0;       //接收状态标记	  
  
void uart_init(u32 bound){
  //GPIO端口设置
  GPIO_InitTypeDef GPIO_InitStructure;
	USART_InitTypeDef USART_InitStructure;
	NVIC_InitTypeDef NVIC_InitStructure;
	 
	RCC_APB2PeriphClockCmd(RCC_APB2Periph_USART1|RCC_APB2Periph_GPIOA, ENABLE);	//使能USART1，GPIOA时钟
  
	//USART1_TX   GPIOA.9
  GPIO_InitStructure.GPIO_Pin = GPIO_Pin_9; //PA.9
  GPIO_InitStructure.GPIO_Speed = GPIO_Speed_50MHz;
  GPIO_InitStructure.GPIO_Mode = GPIO_Mode_AF_PP;	//复用推挽输出
  GPIO_Init(GPIOA, &GPIO_InitStructure);//初始化GPIOA.9
   
  //USART1_RX	  GPIOA.10初始化
  GPIO_InitStructure.GPIO_Pin = GPIO_Pin_10;//PA10
  GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IN_FLOATING;//浮空输入
  GPIO_Init(GPIOA, &GPIO_InitStructure);//初始化GPIOA.10  

  //Usart1 NVIC 配置
  NVIC_InitStructure.NVIC_IRQChannel = USART1_IRQn;
	NVIC_InitStructure.NVIC_IRQChannelPreemptionPriority=3 ;//抢占优先级3
	NVIC_InitStructure.NVIC_IRQChannelSubPriority = 3;		//子优先级3
	NVIC_InitStructure.NVIC_IRQChannelCmd = ENABLE;			//IRQ通道使能
	NVIC_Init(&NVIC_InitStructure);	//根据指定的参数初始化VIC寄存器
  
   //USART 初始化设置

	USART_InitStructure.USART_BaudRate = bound;//串口波特率
	USART_InitStructure.USART_WordLength = USART_WordLength_8b;//字长为8位数据格式
	USART_InitStructure.USART_StopBits = USART_StopBits_1;//一个停止位
	USART_InitStructure.USART_Parity = USART_Parity_No;//无奇偶校验位
	USART_InitStructure.USART_HardwareFlowControl = USART_HardwareFlowControl_None;//无硬件数据流控制
	USART_InitStructure.USART_Mode = USART_Mode_Rx | USART_Mode_Tx;	//收发模式

  USART_Init(USART1, &USART_InitStructure); //初始化串口1
  USART_ITConfig(USART1, USART_IT_RXNE, ENABLE);//开启串口接受中断
  USART_Cmd(USART1, ENABLE);                    //使能串口1 
  setlocale(LC_ALL,"C");

}

void USART1_IRQHandler(void)                	//串口1中断服务程序
{
	
} 


#endif	

