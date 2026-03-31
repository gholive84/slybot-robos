//+------------------------------------------------------------------+
//|                                                 SLYBOT_ATR_V1.mq5 |
//|                                                 Slybot Automacoes |
//|                                         https://www.slybot.com.br |
//+------------------------------------------------------------------+
#property copyright "Slybot Sistemas de Automacao"
#property link      "https://www.slybot.com.br"
#property version   "1.0" // Versão otimizada e corrigida

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <JAson.mqh>

CTrade         m_trade;
CPositionInfo  m_position;

#resource "\\Images\\slybot_final.bmp";

string API_URL = "https://slybot.com.br/wp-json/slybot/v1/validate";
string API_SECRET = "SlyBot$SecureKey#2026!Xv8@Lm4^Qp7Zt2";

datetime last_validation = 0;
bool license_valid = false;

enum Estrategia
{
   Divisor01, //--------------CONTRA TENDÊNCIA
   COMPRA,  // Compra quando cai   
   VENDA,   // Vende quando sobe   
   COMPRA_E_VENDA_CONTRA, //Compra qdo cai e vende qdo sobe
   Divisor02,//---------------A FAVOR TENDÊNCIA
   COMPRA_SOBE,  // Compra quando sobe 
   VENDA_CAI,   // Vende quando cai
   COMPRA_E_VENDA_TENDENCIA //Compra qdo sobe e vende qdo cai
   
};

//--- Variáveis Input
input string       LICENSE_KEY             = "";     // Insira sua Licença
input string       nome_estrategia         = "";     // Insira o nome da estrategia
input group "Estratégias ------------------------------------";
input Estrategia   estrategia              = COMPRA;     // Estratégia de Entrada
input bool         trade_unico             = true;       // Somente 1 trade por dia. Falso = compra e vende no mesmo dia
input int          max_posicoes_ativas     = 5;          // Número máximo de posições ativas permitido (Mesmo Magic Number)
input bool         linhas                  = true;       // Desenhar linhas no Gráfico

input group "ATR - Configuração ----------------------------";
input ENUM_TIMEFRAMES ATR_Timeframe        = PERIOD_CURRENT; // Timeframe do ATR
input int          ATR_Period              = 14;             // Periodo do ATR

input group " OPERAÇÃO DE ALTA ------------------------------";
input double       ATR_Entry_Alta          = 0.40;       // ATR entrada de alta
input double       ATR_SL_Alta             = 1.00;       // ATR stop de alta
input double       ATR_TP_Alta             = 1.00;       // ATR gain de alta

input group " OPERAÇÃO DE QUEDA -----------------------------";
input double       ATR_Entry_Queda         = 0.40;       // ATR entrada de queda
input double       ATR_SL_Queda            = 1.00;       // ATR stop de queda
input double       ATR_TP_Queda            = 1.00;       // ATR gain de queda

input group "BREAKEVEN --------------------------------";
input bool         USAR_BREAKEVEN          = false;       // Usar BREAKEVEN?
input double       BE_ATR_Alta             = 0.50;        // ATR para ativar BE de alta
input double       BE_ATR_Queda            = 0.50;        // ATR para ativar BE de queda
input double       BE_SOBRA                = 0.0;         // Pontos/centavos de lucro ao ativar BE

input group "TRAILLING --------------------------------";
input bool         USAR_TRAILING           = false;       // Se Ativo, ignora BREAKEVEN
input double       TRAILING_ATR_Alta       = 0.50;        // Trailing em ATR para alta
input double       TRAILING_ATR_Queda      = 0.50;        // Trailing em ATR para queda
input double       TRAILING_START_ATR      = 0.50;        // ATR mínimo para iniciar trailing


input group "HORÁRIOS ---------------------------------------";
input int          hora_entrada            = 900;         // A partir desse horario permite operar
input int          hora_saida              = 1800;        // Horário de fechamento de ordens caso não atinja alvos
input int          hora_limite             = 1600;        // Horário limite para ordens

input group "Gestão de Risco --------------------------------";
input double       SaldoInicial            = 1000.0;      // Saldo inicial para cálculo de lucro acumulado
input double       num_lots                = 1.0;         // Numero de Lotes fixo ("0" =  gestão automática)
input double       fator_lots              = 1.0;         // Fator de Lote por saldo
input double       saldo_por_lots          = 1000;        // Gestão Automática | Saldo para cada Lote/Contrato
input double       lots_maximo             = 1000;        // Lote Máximo ( "0" = desabilitado)
input double       loss                    = 50000;       // Loss diário de segurança

input group "Parâmetros ------------------------------";
input ENUM_TIMEFRAMES mm_tempo_grafico     = PERIOD_CURRENT; // Tempo gráfico
input ulong        magicNumber             = 121212;     // Magic Number


//--- Variáveis internas
double g_fechaAnterior, g_precoEntradaC, g_precoEntradaV, g_precoAtual, g_fechamentoBarra, g_percentualQueda, g_percentualAlta, g_aberturaDia, g_loteFinal;
int g_currentTime;

double minima_dia, maxima_dia;
string max_min_dia = "neutro";




// --- variáveis globais

string g_licensePlan = "---";
string g_licenseExpiration = "---";
string g_licenseStatus = "Validando...";
color  g_licenseColor = clrYellow;




int atrHandle = INVALID_HANDLE;
int atrPeriod = 14;
ENUM_TIMEFRAMES atrTF = PERIOD_M5;
double g_atr = 0.0;


bool g_fechouPorHorario = false;
int  g_diaControle     = -1;

// NOVAS VARIÁVEIS PARA GESTÃO DE RISCO BASEADA EM LUCRO
double g_lucroAcumulado = 0.0; // NOVO NOME para clareza
double g_saldoBaseLotes = 0.0;
double g_lucroMensal = 0.0; // Para o painel futuro


//+------------------------------------------------------------------+
//| CONFIGURAÇÃO NOVA DO PAINEL PREMIUM                              |
//+------------------------------------------------------------------+
#define PANEL_NAME            "DashboardPanel"
#define PANEL_HEADER_NAME     "DashboardHeader"
#define PANEL_BODY_NAME       "DashboardBody"

#define BTN_COLLAPSE          "BTN_COLLAPSE"
#define BTN_POWER             "BTN_POWER"

#define PANEL_WIDTH           360
#define PANEL_HEADER_HEIGHT   40
#define PANEL_BODY_HEIGHT     300

#define PANEL_MARGIN_TOP     80   // 🔥 ajuste aqui para descer o painel

#define PANEL_CORNER          CORNER_LEFT_UPPER

bool g_panelCollapsed = false;
bool g_botLigado      = true;

int lineY = 0;
int lineHeight = 16;




// Variáveis para os objetos de texto
string g_labelNames[] = {
    "Label_StatusLicenca",
    "Label_Plano",
    "Label_Expiracao",
    "Label_Ativo",
    "Label_Lotes",
    "Label_SaldoBase",
    "Label_Hora",
    "Label_PosicaoAberta",
    "Label_SaldoMensal",
    "Label_SaldoTotal"
};



bool g_primeiroStopVenda = false; 
bool g_primeiroStopCompra = false; 
bool g_primeiraOrdem = false; 
bool g_breakeven = false; 

datetime g_dataUltimoTrade = 0;
datetime g_dataUltimoTradeAlta = 0;
datetime g_dataUltimoTradeBaixa = 0;





int GetPanelHeight()
{
   if(g_panelCollapsed)
      return PANEL_HEADER_HEIGHT;
   else
      return PANEL_HEADER_HEIGHT + PANEL_BODY_HEIGHT;
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   fecharOrdens();
   fecharPositions();

   RemoverPainel();

   if(atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(atrHandle);
      atrHandle = INVALID_HANDLE;
   }

   Print("SlyBot removido e painel apagado.");
}

//+------------------------------------------------------------------+
//| Função de Inicialização                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   
 

    Print("=== INICIANDO SLYBOT ===");

   license_valid = ValidateLicense();
   last_validation = TimeCurrent();
   
   if(!license_valid)
   {
      Print("Licença inválida. Robô não irá operar.");
   }
   
    //Print("Licença validada com sucesso.");
   
   EventSetTimer(1); // 1 segundo

   m_trade.SetExpertMagicNumber(magicNumber);
   RemoverPainel();
   CriarPainel(); 
   
   // 🔥 força atualizar os textos
   AtualizarPainel();
   

   // Inicializa ATR corretamente
   atrHandle = iATR(Symbol(), ATR_Timeframe, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("ERRO: Falha ao criar handle do ATR");
      return INIT_FAILED;
   }

   Print("ATR inicializado com sucesso!");
   return INIT_SUCCEEDED;
}


// --- função de leitura rápida
double GetATR_Cached()
{
   if(atrHandle == INVALID_HANDLE) return -1;
   double buf[];
   if(CopyBuffer(atrHandle, 0, 0, 1, buf) != 1) return -1;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Função OnTester                                                  |
//+------------------------------------------------------------------+
double OnTester()
{
    return AccountInfoDouble(ACCOUNT_BALANCE);
}

//+------------------------------------------------------------------+
//| Função principal chamada a cada tick                             |
//+------------------------------------------------------------------+
void OnTick()
{
  
  
   // 🔒 BLOQUEIO IMEDIATO
   if(!license_valid)
   {
      AtualizarPainel();
     // ExpertRemove();

      return;
   }

   // 🔄 REVALIDAÇÃO A CADA 30 MIN
   if(TimeCurrent() - last_validation > 20)
   {
      license_valid = ValidateLicense();
      last_validation = TimeCurrent();
       Print("Licença heck.");

      if(!license_valid)
      {
         Print("Licença revogada.");
         AtualizarPainel();
        // ExpertRemove();

         return;
      }
   }

    
     //ExpertRemove();

   //if(!license_valid)
    //  return;
      
  // 🔴 BOTÃO OFF BLOQUEIA TUDO
   if(!g_botLigado)
   {
      AtualizarPainel();
      return;
   }

  
    
  double atr = GetATR_Cached();

// Só grava o ATR se for válido
if(atr > 0)
    g_atr = atr;

// NÃO dar return aqui

   ResetarControleDiario();

   
   GerenciarPosicoesAtivas();
   GerenciarHorarios();

   datetime dataAtual = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

   if (NovoCandle())
   {  
      GerenciarPerdasGanhosDiarios();
      AtualizarGestaoDeRisco(); // <-- ADICIONE ESTA LINHA
      AtualizarDadosDoMercado();
      GetTodayHighLow(minima_dia, maxima_dia);
      CalcularPrecosDeEntrada();
        
      
     
      
      
     
      if (linhas) DesenharLinhas();
      //if(contexto == MINIMA_MAXIMA_DIA && g_currentTime >= hora_entrada) DesenharLinhas();
      g_loteFinal = (num_lots != 0) ? num_lots : CalcularLotes();
   }

   ExecutarEstrategias(dataAtual);
  
  
  // 6. Gestão de Posições Abertas (Onde o SL/TP e Trailing acontecem)
    // Chamamos a função mestre de gestão de risco
    GerenciarRiscoPosicoes();

   
   
   
   
   
   AtualizarPainel(); // <-- ADICIONE ESTA LINHA
   
   
}



void OnTimer()
{
   ResetarControleDiario();
   GerenciarHorarios();
}




//+------------------------------------------------------------------+
//| Funções Auxiliares (Refatoradas)                                 |
//+------------------------------------------------------------------+

void GerenciarPerdasGanhosDiarios()
{
   if (OpenPositionsProfit() < -loss)
   {
      fecharOrdens();
      fecharPositions();
   }
}

void GerenciarPosicoesAtivas()
{
   Comment("\nPosições ativas com magic number ", magicNumber, ": ", ContarPosicoesAtivas());
   if (ContarPosicoesAtivas() >= max_posicoes_ativas)
   {
      Print("Número máximo de posições ativas atingido: ", max_posicoes_ativas, ". Bloqueando novas operações.");
      fecharOrdens();
   }
}

void GerenciarHorarios()
{
   datetime timeNow = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(timeNow, tm);
   g_currentTime = tm.hour * 100 + tm.min;

   if (g_currentTime >= hora_limite && OrdemPendenteExistente()) fecharOrdens();
   
  // if (g_currentTime >= hora_saida)
  // {
  //    fecharOrdens();
   //   fecharPositions();
   //   g_primeiraOrdem = false;
   //   g_primeiroStopCompra = false;
   //   g_primeiroStopVenda = false;
   //   g_breakeven = false;
     // max_min_dia = "neutro";
    //  ObjectDelete(0, "LinhaPercentualAlta");
     // ObjectDelete(0, "LinhaPercentualQueda");
     // Comment("Fechamento pelo horário");
  // }
   
   
   if (g_currentTime >= hora_saida && !g_fechouPorHorario)
{
   Print("⏰ Fechamento por horário acionado: ",
         TimeToString(TimeCurrent(), TIME_SECONDS));
         
         max_min_dia = "neutro";
      ObjectDelete(0, "LinhaPercentualAlta");
      ObjectDelete(0, "LinhaPercentualQueda");

   fecharOrdens();
   fecharPositions();

   g_fechouPorHorario = true;
}
   
   
}



//+------------------------------------------------------------------+
//| Variável global para armazenar o lucro acumulado (realizado)     |
//| durante a execução do robô.                                      |
//+------------------------------------------------------------------+
double g_lucroAcumuladoRealizado = 0.0; // Adicione esta variável global

//+------------------------------------------------------------------+
//| Função para calcular lucro acumulado e saldo base para lotes     |
//+------------------------------------------------------------------+
void AtualizarGestaoDeRisco()
{
   // 1. O Saldo Base para Lotes é o Saldo Inicial + Lucro Acumulado Realizado
   g_saldoBaseLotes = SaldoInicial + g_lucroAcumuladoRealizado; 
   
   // 2. O Lucro Acumulado (para exibição) será o lucro/prejuízo das posições abertas (não realizado)
   g_lucroAcumulado = OpenPositionsProfit(); // Lucro/Prejuízo em aberto
   
   // 3. Calcula o lucro mensal (mantido)
   g_lucroMensal = CalcularLucroMensal(); 
}







void AtualizarDadosDoMercado()
{

  


   g_fechaAnterior = iClose(_Symbol, PERIOD_D1, 1);
   g_aberturaDia = iOpen(Symbol(), PERIOD_D1, 0);
   g_precoAtual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   MqlRates BarData[1];
   CopyRates(Symbol(), Period(), 0, 1, BarData);
   g_fechamentoBarra = BarData[0].close;
}

void CalcularPrecosDeEntrada()
{
   if(g_atr <= 0)
   {
      Print("ATR inválido, não é possível calcular preços de entrada.");
      return;
   }

   g_precoEntradaC = g_aberturaDia + (g_atr * ATR_Entry_Alta);
   g_precoEntradaV = g_aberturaDia - (g_atr * ATR_Entry_Queda);
}










void ExecutarEstrategias(datetime dataAtual)
{
   //==============================================================
   //  CONDIÇÕES INICIAIS PARA PERMITIR OPERAÇÃO
   //==============================================================

   // Pode operar se:
   // - Não há posição aberta (com mesmo magic)
   // - Não há ordem pendente aberta (com mesmo magic)
   // - Está dentro da janela de horário configurada
   bool podeOperar =
          !verificarPositions() &&
          !OrdemPendenteExistente() &&
          g_currentTime < hora_saida &&
          g_currentTime > hora_entrada;

   // Trade único por dia (impede operações repetidas no mesmo dia)
   bool tradeUnicoDia = (dataAtual != g_dataUltimoTrade);


   //==============================================================
   //           ESTRATÉGIAS CONTRA A TENDÊNCIA
   //==============================================================
   // Executa apenas:
   // - No horário permitido
   // - Sem posições
   // - Sem ordens pendentes
   // - O dia ainda não operou
   // - Primeira ordem ainda não foi enviada
   if (podeOperar && tradeUnicoDia && !g_primeiraOrdem)
   {
      //----------------------------------------------------------
      //                   COMPRA LIMIT
      //----------------------------------------------------------
      if (estrategia == COMPRA)
      {
         if (m_trade.BuyLimit(g_loteFinal, g_precoEntradaV, _Symbol,
                              0.0, 0.0, ORDER_TIME_DAY, 0,
                              "Compra quando cai"))
         {
            Print("Ordem pendente de compra criada em: ",
                  DoubleToString(g_precoEntradaV, _Digits));

            g_dataUltimoTrade = dataAtual;
            g_primeiraOrdem   = true;
         }
         else Print("Erro ao criar ordem de compra: ", GetLastError());
      }

      //----------------------------------------------------------
      //                   VENDA LIMIT
      //----------------------------------------------------------
      else if (estrategia == VENDA)
      {
         if (m_trade.SellLimit(g_loteFinal, g_precoEntradaC, _Symbol,
                               0.0, 0.0, ORDER_TIME_DAY, 0,
                               "Vende quando Sobe"))
         {
            Print("Ordem pendente de venda criada em: ",
                  DoubleToString(g_precoEntradaC, _Digits));

            g_dataUltimoTrade = dataAtual;
            g_primeiraOrdem   = true;
         }
         else Print("Erro ao criar ordem de venda: ", GetLastError());
      }

      //----------------------------------------------------------
      //           COMPRA E VENDA CONTRA A TENDÊNCIA
      //----------------------------------------------------------
      else if (estrategia == COMPRA_E_VENDA_CONTRA)
      {
         // ----- COMPRA -----
         if (m_trade.BuyLimit(g_loteFinal, g_precoEntradaV, _Symbol,
                              0.0, 0.0, ORDER_TIME_DAY, 0,
                              "Compra quando cai"))
         {
            Print("Ordem pendente de compra criada em: ",
                  DoubleToString(g_precoEntradaV, _Digits));
         }
         else Print("Erro ao criar ordem de compra: ", GetLastError());

         // ----- VENDA -----
         if (m_trade.SellLimit(g_loteFinal, g_precoEntradaC, _Symbol,
                               0.0, 0.0, ORDER_TIME_DAY, 0,
                               "Vende quando Sobe"))
         {
            Print("Ordem pendente de venda criada em: ",
                  DoubleToString(g_precoEntradaC, _Digits));
         }
         else Print("Erro ao criar ordem de venda: ", GetLastError());
      }
   }


   //==============================================================
   //              ESTRATÉGIAS A FAVOR DA TENDÊNCIA
   //==============================================================
   // Ativadas SOMENTE após a hora_entrada
   if (g_currentTime > hora_entrada)
   {
      //----------------------------------------------------------
      //         COMPRA A MERCADO → tendência de alta
      //----------------------------------------------------------
      if (estrategia == COMPRA_SOBE &&
          g_fechamentoBarra > g_precoEntradaC &&
          tradeUnicoDia)
      {
         if (m_trade.Buy(g_loteFinal, _Symbol, 0.0, 0.0, 0.0,
                         "comprado a mercado"))
         {
            Print("Ordem de compra a mercado executada em: ",
                  DoubleToString(g_fechamentoBarra, _Digits));

            g_dataUltimoTrade = dataAtual;
            ajustarStopLoss();   // Ajusta stops após execução
         }
         else Print("Erro ao executar compra a mercado: ", GetLastError());
      }

      //----------------------------------------------------------
      //         VENDA A MERCADO → tendência de baixa
      //----------------------------------------------------------
      else if (estrategia == VENDA_CAI &&
               g_fechamentoBarra < g_precoEntradaV &&
               tradeUnicoDia)
      {
         if (m_trade.Sell(g_loteFinal, _Symbol, 0.0, 0.0, 0.0,
                          "venda a mercado"))
         {
            Print("Ordem de venda a mercado executada em: ",
                  DoubleToString(g_fechamentoBarra, _Digits));

            g_dataUltimoTrade = dataAtual;
            ajustarStopLoss();
         }
         else Print("Erro ao executar venda a mercado: ", GetLastError());
      }


      //----------------------------------------------------------
      //        COMPRA E VENDA A FAVOR DA TENDÊNCIA
      //----------------------------------------------------------
      else if (estrategia == COMPRA_E_VENDA_TENDENCIA)
      {
         //======================================================
         //             MODO "NÃO TRADE ÚNICO"
         //======================================================
         if (!trade_unico)
         {
            // ----- COMPRA -----
            if (g_fechamentoBarra > g_precoEntradaC &&
                dataAtual != g_dataUltimoTradeAlta)
            {
               if (m_trade.Buy(g_loteFinal, _Symbol, 0.0, 0.0, 0.0,
                               "comprado a mercado"))
               {
                  g_dataUltimoTradeAlta = dataAtual;
                  Print("Compra a mercado (tendência) executada.");
               }
               else Print("Erro ao executar compra a mercado (tendência): ", GetLastError());
            }

            // ----- VENDA -----
            else if (g_fechamentoBarra < g_precoEntradaV &&
                     dataAtual != g_dataUltimoTradeBaixa)
            {
               if (m_trade.Sell(g_loteFinal, _Symbol, 0.0, 0.0, 0.0,
                                "venda a mercado"))
               {
                  g_dataUltimoTradeBaixa = dataAtual;
                  Print("Venda a mercado (tendência) executada.");
               }
               else Print("Erro ao executar venda a mercado (tendência): ", GetLastError());
            }
         }

         //======================================================
         //             MODO "TRADE ÚNICO"
         //======================================================
         else if (trade_unico && tradeUnicoDia)
         {
            // ----- COMPRA -----
            if (g_fechamentoBarra > g_precoEntradaC)
            {
               if (m_trade.Buy(g_loteFinal, _Symbol, 0.0, 0.0, 0.0,
                               "comprado a mercado"))
               {
                  g_dataUltimoTrade = dataAtual;
                  Print("Compra a mercado (tendência, trade único) executada.");
               }
               else Print("Erro ao executar compra a mercado (tendência, trade único): ", GetLastError());
            }

            // ----- VENDA -----
            else if (g_fechamentoBarra < g_precoEntradaV)
            {
               if (m_trade.Sell(g_loteFinal, _Symbol, 0.0, 0.0, 0.0,
                                "venda a mercado"))
               {
                  g_dataUltimoTrade = dataAtual;
                  Print("Venda a mercado (tendência, trade único) executada.");
               }
               else Print("Erro ao executar venda a mercado (tendência, trade único): ", GetLastError());
            }
         }
      }
   }
}



void GerenciarRiscoPosicoes()
{
    if (!verificarPositions()) return;

    // 1. Garante o Stop Loss Inicial (Sempre)
    ajustarStopLoss(); 

    // 2. Breakeven SEMPRE ativo (se o usuário ligou a flag)
    // Ele vai proteger o trade em 0.5%
    if (USAR_BREAKEVEN)
    {
        StopEven();
    }

    // 3. Trailing Stop (Só entra se o preço bater o START)
    if (USAR_TRAILING)
    {
        // Aqui dentro, a primeira linha deve ser o gatilho do TRAILING_START
        // Se o preço estiver abaixo do Start, esta função não faz NADA
        GerenciarTrailingStop();
    }
}







void ajustarStopLoss()
{
   for (int i = 0; i < PositionsTotal(); i++)
   {
       ulong ticket = PositionGetTicket(i);
       if (PositionSelectByTicket(ticket))
       {
           ulong magic = PositionGetInteger(POSITION_MAGIC);
           string symbol = PositionGetString(POSITION_SYMBOL);

           if (magic == magicNumber && symbol == _Symbol)
           {
               double precoExecucao = PositionGetDouble(POSITION_PRICE_OPEN);
               long tipo = PositionGetInteger(POSITION_TYPE);
               double preco_loss = 0.0;
               double preco_gain = 0.0;

               // ===========================================================
               //             BLOCO ATR
               // ===========================================================
               if (g_atr <= 0)
               {
                   Print("ATR inválido no ajustarStopLoss()");
                   return;
               }

               if (tipo == POSITION_TYPE_BUY && !g_primeiroStopCompra)
               {
                   preco_loss = NormalizeDouble(precoExecucao - (g_atr * ATR_SL_Alta), _Digits);
                   preco_gain = NormalizeDouble(precoExecucao + (g_atr * ATR_TP_Alta), _Digits);
                   g_primeiroStopCompra = true;
               }
               else if (tipo == POSITION_TYPE_SELL && !g_primeiroStopVenda)
               {
                   preco_loss = NormalizeDouble(precoExecucao + (g_atr * ATR_SL_Queda), _Digits);
                   preco_gain = NormalizeDouble(precoExecucao - (g_atr * ATR_TP_Queda), _Digits);
                   g_primeiroStopVenda = true;
               }

               // ===========================================================
               //             APLICAÇÃO DO SL/TP (MANTIDO)
               // ===========================================================
               if (preco_loss != 0.0 || preco_gain != 0.0)
               {
                   if (m_trade.PositionModify(ticket, preco_loss, preco_gain))
                   {   
                       Print("------------------------------------------------------------------------------RODOU STOP LOSS");
                       Print("StopLoss ajustado → SL=", DoubleToString(preco_loss, _Digits), " TP=", DoubleToString(preco_gain, _Digits));
                   }
                   else
                   {
                       Print("Erro ao ajustar SL/TP: ", GetLastError());
                   }
               }
           }
       }
   }
}






//+------------------------------------------------------------------+
//| Função para calcular lotes inteiros                              |
//+------------------------------------------------------------------+
//int CalcularLotes()
//{
   // O saldo usado para o cálculo é o Saldo Inicial (g_saldoBaseLotes)
 //  double saldo = g_saldoBaseLotes; 
  // int lotes = (int)MathFloor(saldo / saldo_por_lots);

  // if(lotes < 1) lotes = 1; 
  // if (lotes > lots_maximo && lots_maximo != 0) lotes = (int)lots_maximo;  // Cast para int
  // return lotes;
//}


//+------------------------------------------------------------------+
//| Função para calcular lotes por faixas de saldo                   |
//+------------------------------------------------------------------+
double CalcularLotes()
{
   double saldo = g_saldoBaseLotes;

   // Quantos blocos completos do 'saldo_por_lots' foram atingidos
   int blocos = (int)MathFloor(saldo / saldo_por_lots);

   // Lotes = blocos * fator_lote, mas garante pelo menos 'fator_lote'
   double lotes_calc = MathMax(fator_lots, blocos * fator_lots);

   // Limita ao máximo, se definido
   if(lots_maximo > 0 && lotes_calc > lots_maximo)
      lotes_calc = lots_maximo;

   // Normaliza (opcional) — use casas decimais compatíveis com seu broker
   return NormalizeDouble(lotes_calc, 2);
}




//+------------------------------------------------------------------+
//| Função para calcular o lucro acumulado no mês atual              |
//| Compatível com contas hedge e multi-deals                        |
//+------------------------------------------------------------------+
double CalcularLucroMensal()
{
    double lucro_mensal = 0.0;

    // 1. Data de início do mês atual
    MqlDateTime data_atual;
    TimeToStruct(TimeCurrent(), data_atual);

    MqlDateTime inicio_mes_struct;
    inicio_mes_struct.year = data_atual.year;
    inicio_mes_struct.mon  = data_atual.mon;
    inicio_mes_struct.day  = 1;
    inicio_mes_struct.hour = 0;
    inicio_mes_struct.min  = 0;
    inicio_mes_struct.sec  = 0;

    datetime inicio_do_mes = StructToTime(inicio_mes_struct);

    // 2. Seleciona histórico de deals do mês
    if(!HistorySelect(inicio_do_mes, TimeCurrent()))
    {
        Print("Erro ao selecionar histórico: ", GetLastError());
        return 0.0;
    }

    int total_deals = HistoryDealsTotal();

    // 3. Itera sobre todos os deals do histórico
    for(int i = 0; i < total_deals; i++)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);

        // Obtém propriedades relevantes
        string deal_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
        long deal_magic    = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
        long deal_entry    = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
        double deal_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
        double commission  = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
        double swap        = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
        double fee         = HistoryDealGetDouble(deal_ticket, DEAL_FEE);

        // 4. Filtra por símbolo e magic number (permitindo 0)
        if(deal_symbol == _Symbol && (deal_magic == magicNumber || deal_magic == 0))
        {
            // Considera apenas deals com resultado financeiro real
            if(deal_entry == DEAL_ENTRY_OUT || deal_profit != 0)
            {
                double lucro_total = deal_profit + commission + swap + fee;
                lucro_mensal += lucro_total;
            }
        }
    }

    return lucro_mensal;
}



//+------------------------------------------------------------------+
//| Função para calcular o lucro acumulado REALIZADO (deals fechados)|
//+------------------------------------------------------------------+
double CalcularLucroAcumuladoRealizado()
{
    double lucro_total = 0.0;
    
    // Seleciona todo o histórico disponível (desde 0)
    if (!HistorySelect(0, TimeCurrent()))
    {
        Print("Erro ao selecionar o histórico de deals: ", GetLastError());
        return 0.0;
    }
    
    int total_deals = HistoryDealsTotal();
    for (int i = 0; i < total_deals; i++)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        
        long deal_magic = 0;
        string deal_symbol = "";
        long deal_entry_type = 0;
        double deal_profit = 0.0;
        
        // Tenta obter as propriedades do deal (usando a sintaxe corrigida)
        if (HistoryDealGetInteger(deal_ticket, DEAL_MAGIC, deal_magic) &&
            HistoryDealGetString(deal_ticket, DEAL_SYMBOL, deal_symbol) &&
            HistoryDealGetInteger(deal_ticket, DEAL_ENTRY, deal_entry_type) &&
            HistoryDealGetDouble(deal_ticket, DEAL_PROFIT, deal_profit))
        {
            // Filtrar por Magic Number e Símbolo
            if (deal_magic == magicNumber && deal_symbol == _Symbol)
            {
                // Apenas deals de fechamento (lucro/prejuízo)
                if (deal_entry_type == DEAL_ENTRY_OUT)
                {
                    lucro_total += deal_profit;
                }
            }
        }
    }
    
    return lucro_total;
}







void StopEven()
{
   if(!USAR_BREAKEVEN) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) != magicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

         double precoAbertura = PositionGetDouble(POSITION_PRICE_OPEN);
         double precoAtual = PositionGetDouble(POSITION_PRICE_CURRENT);
         double slAtual = PositionGetDouble(POSITION_SL);
         long tipo = PositionGetInteger(POSITION_TYPE);
         
         // Cálculo do gatilho em ATR
         if(tipo == POSITION_TYPE_BUY)
         {
            double gatilhoBE = precoAbertura + (g_atr * BE_ATR_Alta);
            if(precoAtual >= gatilhoBE && (slAtual < precoAbertura || slAtual == 0))
            {
               double novoSL = NormalizeDouble(precoAbertura + (BE_SOBRA * _Point), _Digits);
               m_trade.PositionModify(ticket, novoSL, PositionGetDouble(POSITION_TP));
            }
         }
         else if(tipo == POSITION_TYPE_SELL)
         {
            double gatilhoBE = precoAbertura - (g_atr * BE_ATR_Queda);
            if(precoAtual <= gatilhoBE && (slAtual > precoAbertura || slAtual == 0))
            {
               double novoSL = NormalizeDouble(precoAbertura - (BE_SOBRA * _Point), _Digits);
               m_trade.PositionModify(ticket, novoSL, PositionGetDouble(POSITION_TP));
            }
         }
      }
   }
}


void GerenciarTrailingStop()
{
   if(!USAR_TRAILING) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         // Filtro de Magic Number e Símbolo
         if(PositionGetInteger(POSITION_MAGIC) != magicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

         double precoAbertura = PositionGetDouble(POSITION_PRICE_OPEN);
         double precoAtual    = PositionGetDouble(POSITION_PRICE_CURRENT);
         double slAtual       = PositionGetDouble(POSITION_SL);
         long tipo            = PositionGetInteger(POSITION_TYPE);
         
         if(tipo == POSITION_TYPE_BUY)
         {
            // 1. Gatilho em ATR
            double gatilhoStart = precoAbertura + (g_atr * TRAILING_START_ATR);
            if(precoAtual < gatilhoStart) continue;

            // 2. Distância do trailing em ATR
            double novoSL = NormalizeDouble(precoAtual - (g_atr * TRAILING_ATR_Alta), _Digits);

            // 3. Só sobe o SL
            if(novoSL > slAtual || slAtual == 0)
            {
               if(!m_trade.PositionModify(ticket, novoSL, PositionGetDouble(POSITION_TP)))
                  Print("Erro no Trailing Compra: ", GetLastError());
            }
         }
         else if(tipo == POSITION_TYPE_SELL)
         {
            // 1. Gatilho em ATR
            double gatilhoStart = precoAbertura - (g_atr * TRAILING_START_ATR);
            if(precoAtual > gatilhoStart) continue;

            // 2. Distância do trailing em ATR
            double novoSL = NormalizeDouble(precoAtual + (g_atr * TRAILING_ATR_Queda), _Digits);

            // 3. Só desce o SL
            if(novoSL < slAtual || slAtual == 0)
            {
               if(!m_trade.PositionModify(ticket, novoSL, PositionGetDouble(POSITION_TP)))
                  Print("Erro no Trailing Venda: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Funções de Verificação e Auxiliares (Manter ou Adaptar)          |
//+------------------------------------------------------------------+

// Função para verificar se é um novo candle
bool NovoCandle()
{
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, mm_tempo_grafico, 0);
    if (last_bar_time != current_bar_time)
    {
        last_bar_time = current_bar_time;
        return true;
    }
    return false;
}

// Função para contar posições abertas pelo magic number
int ContarPosicoesAtivas()
{
    int contador = 0;
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
        {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if (magic == magicNumber)  // Verifica o magic number
                contador++;
        }
    }
    return contador;
}

// Função para verificar se existem posições abertas com o magic number
bool verificarPositions()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
        {
            if (PositionGetInteger(POSITION_MAGIC) == magicNumber)
            {
                return true;
            }
        }
    }
    return false;
}

// Função para verificar se existe ordem pendente com o magic number
bool OrdemPendenteExistente()
{
    for (int i = 0; i < OrdersTotal(); i++)
    {
        ulong ticket = OrderGetTicket(i);
        if (OrderSelect(ticket))
        {
            if (OrderGetInteger(ORDER_MAGIC) == magicNumber)
            {
                return true;
            }
        }
    }
    return false;
}

// Função para fechar todas as ordens pendentes com o magic number
void fecharOrdens()
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if (OrderSelect(ticket))
        {
            if (OrderGetInteger(ORDER_MAGIC) == magicNumber)
            {
                m_trade.OrderDelete(ticket);
            }
        }
    }
}

// Função para fechar todas as posições abertas com o magic number
void fecharPositions()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket))
        {
            if (PositionGetInteger(POSITION_MAGIC) == magicNumber)
            {
                if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                {
                    m_trade.PositionClose(ticket, PositionGetDouble(POSITION_VOLUME)); // Usando PositionClose
                }
                else
                {
                    m_trade.PositionClose(ticket, PositionGetDouble(POSITION_VOLUME)); // Usando PositionClose
                }
            }
        }
    }
}

// Função para desenhar linhas no gráfico
void DesenharLinhas()
{
    ObjectDelete(0, "LinhaPercentualAlta");
    ObjectDelete(0, "LinhaPercentualQueda");

    if (ObjectFind(0, "LinhaPercentualQueda") == -1)
    {
        ObjectCreate(0, "LinhaPercentualQueda", OBJ_HLINE, 0, 0, g_precoEntradaV);
        ObjectSetInteger(0, "LinhaPercentualQueda", OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, "LinhaPercentualQueda", OBJPROP_STYLE, STYLE_DASH);
        ObjectSetInteger(0, "LinhaPercentualQueda", OBJPROP_WIDTH, 1);
        ObjectSetString(0, "LinhaPercentualQueda", OBJPROP_TEXT, "Venda: " + DoubleToString(g_precoEntradaV, _Digits));
    }
    if (ObjectFind(0, "LinhaPercentualAlta") == -1)
    {
        ObjectCreate(0, "LinhaPercentualAlta", OBJ_HLINE, 0, 0, g_precoEntradaC);
        ObjectSetInteger(0, "LinhaPercentualAlta", OBJPROP_COLOR, clrGreen);
        ObjectSetInteger(0, "LinhaPercentualAlta", OBJPROP_STYLE, STYLE_DASH);
        ObjectSetInteger(0, "LinhaPercentualAlta", OBJPROP_WIDTH, 1);
        ObjectSetString(0, "LinhaPercentualAlta", OBJPROP_TEXT, "Compra: " + DoubleToString(g_precoEntradaC, _Digits));
    }
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Get All Open Positions Profit                                    |
//+------------------------------------------------------------------+
double OpenPositionsProfit()
{
    double allProfit = 0;
    double teste = 0;
    if(PositionsTotal() > 0)
        for(int i = 0; i < PositionsTotal(); i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
                if(PositionGetInteger(POSITION_MAGIC) == magicNumber)
                    if(PositionGetString(POSITION_SYMBOL) == _Symbol)
                        allProfit += PositionGetDouble(POSITION_PROFIT);
        }
     
    // REMOVA AS LINHAS QUE USAM LucroDiario()
    // double teste = LucroDiario() + allProfit; 
    // Comment("\nLucro diário  ", teste);
    // return teste;
    
  //  Comment("\nLucro em Aberto: ", DoubleToString(allProfit, 2)); // Novo comentário para clareza
    return allProfit; // Retorna APENAS o lucro das posições abertas
}

// Função auxiliar LucroDiario (assumindo que existia no código original ou é uma função a ser implementada)
// Se esta função não existe, ela precisará ser implementada ou removida a chamada.
// Para fins de correção, estou adicionando um stub.
double LucroDiario()
{
    // Implemente a lógica para calcular o lucro diário aqui
    // Por exemplo, pode ser a soma dos lucros de todas as operações fechadas no dia
    return 0.0; // Retorno de exemplo
}


//+------------------------------------------------------------------+
//| Função de evento chamada em cada transação de negociação         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    // Verifica se a transação é um fechamento de posição (DEAL_ENTRY_OUT)
    if (trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        ulong deal_ticket = trans.deal;
        
        long deal_magic = 0;
        long deal_entry_type = 0;
        double deal_profit = 0.0;
        
        // Seleciona o deal e verifica se é um fechamento do nosso robô
        if (HistoryDealSelect(deal_ticket) &&
            HistoryDealGetInteger(deal_ticket, DEAL_MAGIC, deal_magic) &&
            HistoryDealGetInteger(deal_ticket, DEAL_ENTRY, deal_entry_type) &&
            HistoryDealGetDouble(deal_ticket, DEAL_PROFIT, deal_profit))
        {
            if (deal_magic == magicNumber && deal_entry_type == DEAL_ENTRY_OUT)
            {
                // Adiciona o lucro/prejuízo do deal ao acumulado
                g_lucroAcumuladoRealizado += deal_profit;
                Print("Trade Fechado. Lucro: ", deal_profit, ". Acumulado: ", g_lucroAcumuladoRealizado);
            }
        }
    }
}


//+------------------------------------------------------------------+
//| Retorna a mínima e a máxima do dia atual                        |
//+------------------------------------------------------------------+
void GetTodayHighLow(double &dayLow, double &dayHigh)
{
   // Handle do símbolo atual
   string symbol = _Symbol;

   // Índice 0 = candle diário atual
   dayLow  = iLow(symbol, PERIOD_D1, 0);
   dayHigh = iHigh(symbol, PERIOD_D1, 0);
}



void ResetarControleDiario()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   // Se mudou o dia → reseta tudo
   if(g_diaControle != t.day)
   {
      g_diaControle = t.day;
      g_fechouPorHorario = false;

      // resets que fazem sentido por dia
      g_primeiraOrdem = false;
      g_primeiroStopCompra = false;
      g_primeiroStopVenda  = false;
      g_breakeven = false;
      
      
      

      Print("🔄 Novo dia detectado — controle diário resetado");
   }
}



void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
                  
                  
{


   Print("Evento: ", id, " | objeto: ", sparam);


   if(id == CHARTEVENT_OBJECT_CLICK)
   {
   
   
   
   // ================= FECHAR TUDO =================
      if(sparam == "BTN_CLOSE_ALL_BG" || sparam == "BTN_CLOSE_ALL_TXT")
      {
         Print("Botão Fechar Tudo acionado.");
      
         fecharOrdens();
         fecharPositions();
      }
         
   
   
   
   // COLAPSAR
   if(sparam == BTN_COLLAPSE)
{
   Print("Collapse clicado");
   g_panelCollapsed = !g_panelCollapsed;

   ObjectSetString(0, BTN_COLLAPSE, OBJPROP_TEXT,
                   g_panelCollapsed ? ">" : "▼");

   ObjectSetInteger(0, PANEL_NAME,
                    OBJPROP_YSIZE,
                    GetPanelHeight());

   string objetosBody[] =
   {
      PANEL_BODY_NAME,

      "LBL_PLANO",
      "LBL_STATUS",
      "LBL_EXPIRA",
      "LBL_ATIVO",
      "LBL_LOTES",
      "LBL_HORA",
      "LBL_GESTAO",
      "LBL_SALDO_BASE",

      "CARD_ABERTO_BG",
      "CARD_ABERTO_TIT",
      "CARD_ABERTO_VAL",

      "CARD_DIA_BG",
      "CARD_DIA_TIT",
      "CARD_DIA_VAL",

      "CARD_SEMANA_BG",
      "CARD_SEMANA_TIT",
      "CARD_SEMANA_VAL",

      "CARD_MES_BG",
      "CARD_MES_TIT",
      "CARD_MES_VAL",

      // 🔥 ADICIONE ISSO
      "BTN_CLOSE_ALL_BG",
      "BTN_CLOSE_ALL_TXT"
   };

   for(int i = 0; i < ArraySize(objetosBody); i++)
   {
      if(ObjectFind(0, objetosBody[i]) >= 0)
      {
         ObjectSetInteger(0,
                          objetosBody[i],
                          OBJPROP_TIMEFRAMES,
                          g_panelCollapsed ? 0 : OBJ_ALL_PERIODS);
      }
   }
   
   
   AtualizarPainel();
   ChartRedraw();
}
      // POWER
      if(sparam == "BTN_POWER_BG" || sparam == "BTN_POWER_TXT")
         {
            g_botLigado = !g_botLigado;
         
            color bgColor = g_botLigado ? clrLime : clrRed;
            string txt    = g_botLigado ? "ON" : "OFF";
         
            ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_BGCOLOR, bgColor);
            ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_BORDER_COLOR, bgColor);
            ObjectSetString(0,  "BTN_POWER_TXT", OBJPROP_TEXT, txt);
         
            ChartRedraw();
         }
   }
}




bool ValidateLicense()
{

    // 🔥 Permitir rodar no testador
   if(MQLInfoInteger(MQL_TESTER))
   {
      Print("Modo Testador detectado - validação ignorada.");
      g_licenseStatus = "TEST MODE";
      g_licenseColor = clrAqua;
      return true;
   }


  if(StringLen(LICENSE_KEY) < 10)
{
   g_licensePlan = "---";
   g_licenseExpiration = "---";
   g_licenseStatus = "Insira sua licença";
   g_licenseColor = clrOrange;

   Print("Chave de licença não informada.");

   return false;
}

   string json =
      "{"
      "\"mt5_login\":\"" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\","
      "\"server\":\"" + AccountInfoString(ACCOUNT_SERVER) + "\","
      "\"license_key\":\"" + LICENSE_KEY + "\","
      "\"broker\":\"" + AccountInfoString(ACCOUNT_COMPANY) + "\","
      "\"secret\":\"" + API_SECRET + "\""
      "}";

   char post[];
   int size = StringToCharArray(json, post, 0, StringLen(json));
   ArrayResize(post, size);

   //char result[];
   //string headers;
   int timeout = 5000;

   string headers = "Content-Type: application/json\r\n";
   char result[];
   int res = WebRequest(
      "POST",
      API_URL,
      headers,
      timeout,
      post,
      result,
      headers
   );
   
   
    
  
   

  if(res == -1)
{
   Print("Erro WebRequest: ", GetLastError());

   g_licensePlan = "---";
   g_licenseExpiration = "---";
   g_licenseStatus = "Servidor offline";
   g_licenseColor = clrRed;

   return false;
}

   string response = CharArrayToString(result);
   
    Print("HTTP Result: ", res);
Print("Response RAW: ", response);
   

   // 🔥 AQUI COMEÇA O PARSE REAL
   CJAVal data;
   if(!data.Deserialize(response))
   {
      Print("Erro ao interpretar JSON.");
      return false;
   }

   bool valid = data["valid"].ToBool();

   if(!valid)
{
   string reason = data["reason"].ToStr();

// 🔹 Tradução dos códigos da API
if(reason == "invalid_license")
   reason = "Licença inválida";

else if(reason == "expired")
   reason = "Licença expirada";

else if(reason == "account_not_allowed")
   reason = "Conta não autorizada";

else if(reason == "server_not_allowed")
   reason = "Servidor não autorizado";

else if(reason == "license_blocked")
   reason = "Licença bloqueada";

else if(reason == "invalid_key")
   reason = "Chave inválida";

else if(reason == "not_found")
   reason = "Licença não encontrada";

// 🔹 Atualiza painel
g_licensePlan = "---";
g_licenseExpiration = "---";
g_licenseStatus = "" + reason;
g_licenseColor = clrRed;

   Print("Licença inválida. Motivo: ", reason);

   return false;
}

   // 🔥 Agora você pode usar os dados
  g_licensePlan = data["plan"].ToStr();
   g_licenseExpiration = data["expiration"].ToStr();
   g_licenseStatus = "✔ Ativa";
   g_licenseColor = clrLime;
   
  




return true;
}






//+------------------------------------------------------------------+
//| Criação completa do Painel Premium                               |
//+------------------------------------------------------------------+
void CriarPainel()
{
   
   
   
   


   // ================================
   // PAINEL PRINCIPAL
   // ================================
   ObjectCreate(0, PANEL_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_YDISTANCE, 10);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_XSIZE, PANEL_WIDTH);
   // altura inicial provisória
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_YSIZE, PANEL_HEADER_HEIGHT + PANEL_BODY_HEIGHT);
   
   //ObjectSetInteger(0, PANEL_NAME, OBJPROP_YSIZE, alturaFinal);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_FILL, true);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_BGCOLOR, C'18,22,35');
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_BORDER_COLOR, C'45,50,70');
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_SELECTABLE, false);

   // ================================
   // HEADER
   // ================================
   ObjectCreate(0, PANEL_HEADER_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_YDISTANCE, 10);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_XSIZE, PANEL_WIDTH);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_YSIZE, PANEL_HEADER_HEIGHT);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_FILL, true);
   ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_BGCOLOR, C'8,12,22');
  ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_BORDER_TYPE, BORDER_FLAT);
ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_BORDER_COLOR, C'28,34,55');
   
  
   
   
   // ============================
   // LOGO DO ROBÔ (RESOURCE)
   // ============================
   
   ObjectCreate(0, "SLYBOT_LOGO", OBJ_BITMAP_LABEL, 0, 0, 0);
   
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_XDISTANCE, 15);
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_YDISTANCE, 15);
   
   ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_FILL, false);
ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_BGCOLOR, clrNONE);
ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_COLOR, clrNONE);
   
   // 🔥 Aqui está o segredo:
   ObjectSetString(0, "SLYBOT_LOGO", OBJPROP_BMPFILE, "::Images\\slybot_final.bmp");
      
   
   

   // Título
   ObjectCreate(0, "LBL_TITLE", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_XDISTANCE, 150);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "LBL_TITLE", OBJPROP_FONTSIZE, 13);
   ObjectSetString(0, "LBL_TITLE", OBJPROP_TEXT, "v1.0");
   
   
   // ================= RESULTADO DIA NO HEADER =================

   ObjectCreate(0, "LBL_RESULTADO_DIA", OBJ_LABEL, 0, 0, 0);
   
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_XDISTANCE, 220);
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_YDISTANCE, 22);
   
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_FONTSIZE, 10);
   
   ObjectSetString(0, "LBL_RESULTADO_DIA", OBJPROP_TEXT, "");
   
   
  
         
   
   
     

   // ================================
   // BOTÃO COLLAPSE
   // ================================
  ObjectCreate(0, BTN_COLLAPSE, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_XDISTANCE, PANEL_WIDTH - 25);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, BTN_COLLAPSE, OBJPROP_TEXT, "▼");
   ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_SELECTABLE, true);

   // ================================
   // BOTÃO POWER CUSTOM
   // ================================
   ObjectCreate(0, "BTN_POWER_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_XDISTANCE, PANEL_WIDTH - 80);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_XSIZE, 40);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_FILL, true);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_BGCOLOR, clrLime);
   ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_BORDER_COLOR, clrLime);

   ObjectCreate(0, "BTN_POWER_TXT", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_XDISTANCE, PANEL_WIDTH - 77);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_YDISTANCE, 22);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, "BTN_POWER_TXT", OBJPROP_TEXT, "ON");

   // ================================
   // BODY
   // ================================
   ObjectCreate(0, PANEL_BODY_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_YDISTANCE, 10 + PANEL_HEADER_HEIGHT);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_XSIZE, PANEL_WIDTH);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_YSIZE, PANEL_BODY_HEIGHT);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_FILL, true);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_BGCOLOR, C'20,26,45');
   
   
   // ================= TEXTOS BODY =================

  int baseY = 10 + PANEL_HEADER_HEIGHT + 15;

   lineY = baseY;
   lineHeight = 16;
   
   
      CriarLinhaBody("LBL_PLANO",  "Plano: ---", 25);
      CriarLinhaBody("LBL_STATUS", "Status: ---", 25);
      CriarLinhaBody("LBL_EXPIRA", "Expira: ---", 25);
      
      
      lineY += 8;
      
      CriarLinhaBody("LBL_ATIVO", "Ativo: ---", 25);
      CriarLinhaBody("LBL_LOTES", "Lotes: ---", 25);
      
      lineY += 8;
      
      CriarLinhaBody("LBL_GESTAO", "Gestão: ---", 25);
      CriarLinhaBody("LBL_SALDO_BASE", "Saldo Base: ---", 25);
      
      lineY += 8;
      
      CriarLinhaBody("LBL_HORA", "Hora: ---", 25);
         
   

   // ================================
   // CARDS (4 COLUNAS)
   // ================================
   int cardY = lineY + 10;

   int margem = 15;
   int espaco = 6;
   int larguraCard = (PANEL_WIDTH - (margem * 2) - (espaco * 3)) / 4;
   int alturaCard = 42;

   CriarCard("CARD_ABERTO_BG", "CARD_ABERTO_TIT", "CARD_ABERTO_VAL", "ABERTO",
             margem, cardY, larguraCard, alturaCard);

   CriarCard("CARD_DIA_BG", "CARD_DIA_TIT", "CARD_DIA_VAL", "DIA",
             margem + larguraCard + espaco, cardY, larguraCard, alturaCard);

   CriarCard("CARD_SEMANA_BG", "CARD_SEMANA_TIT", "CARD_SEMANA_VAL", "SEMANA",
             margem + (larguraCard * 2) + (espaco * 2), cardY, larguraCard, alturaCard);

   CriarCard("CARD_MES_BG", "CARD_MES_TIT", "CARD_MES_VAL", "MÊS",
             margem + (larguraCard * 3) + (espaco * 3), cardY, larguraCard, alturaCard);
             
             
             
             
             
  // ============================
   // BOTÃO FECHAR TODAS OPERAÇÕES
   // ============================
   ObjectCreate(0, "BTN_CLOSE_ALL_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_YDISTANCE, cardY + alturaCard + 15);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_XSIZE, PANEL_WIDTH - 40);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_YSIZE, 28);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_FILL, true);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_BGCOLOR, C'150,20,20');
   ObjectSetInteger(0, "BTN_CLOSE_ALL_BG", OBJPROP_BORDER_COLOR, C'150,20,20');

   ObjectCreate(0, "BTN_CLOSE_ALL_TXT", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_XDISTANCE, PANEL_WIDTH/2);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_YDISTANCE, cardY + alturaCard + 29);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "BTN_CLOSE_ALL_TXT", OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, "BTN_CLOSE_ALL_TXT", OBJPROP_TEXT, "FECHAR TODAS OPERAÇÕES");
   
   
   
   
    int alturaFinal = cardY + alturaCard + 70;
    
    
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_YSIZE, alturaFinal);
   ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_YSIZE, alturaFinal - PANEL_HEADER_HEIGHT);
   
   
   // ================= ZORDER =================

ObjectSetInteger(0, PANEL_NAME, OBJPROP_ZORDER, 0);
ObjectSetInteger(0, PANEL_BODY_NAME, OBJPROP_ZORDER, 1);
ObjectSetInteger(0, PANEL_HEADER_NAME, OBJPROP_ZORDER, 2);

ObjectSetInteger(0, "SLYBOT_LOGO", OBJPROP_ZORDER, 3);
ObjectSetInteger(0, "LBL_TITLE", OBJPROP_ZORDER, 3);

ObjectSetInteger(0, BTN_COLLAPSE, OBJPROP_ZORDER, 5);

ObjectSetInteger(0, "BTN_POWER_BG", OBJPROP_ZORDER, 6);
ObjectSetInteger(0, "BTN_POWER_TXT", OBJPROP_ZORDER, 7);
ObjectSetInteger(0, "LBL_RESULTADO_DIA", OBJPROP_ZORDER, 6);
ObjectSetInteger(0, "LBL_MINI_DASH", OBJPROP_ZORDER, 6);
   
              

   ChartRedraw();
}




void CriarLabelBody(string nome, string texto, int x, int y, color cor, int tamanho = 10)
{
   ObjectCreate(0, nome, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, nome, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, nome, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nome, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, tamanho);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
}



void CriarCard(string nomeBg,
               string nomeTitulo,
               string nomeValor,
               string titulo,
               int x,
               int y,
               int largura,
               int altura)
{
   // ================= FUNDO =================
   ObjectCreate(0, nomeBg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nomeBg, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, nomeBg, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nomeBg, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nomeBg, OBJPROP_XSIZE, largura);
   ObjectSetInteger(0, nomeBg, OBJPROP_YSIZE, altura);
   ObjectSetInteger(0, nomeBg, OBJPROP_FILL, true);
   ObjectSetInteger(0, nomeBg, OBJPROP_BGCOLOR, C'35,45,75');
   ObjectSetInteger(0, nomeBg, OBJPROP_BORDER_COLOR, C'35,45,75');
   ObjectSetInteger(0, nomeBg, OBJPROP_BORDER_TYPE, BORDER_FLAT);

   // ================= TÍTULO =================
   ObjectCreate(0, nomeTitulo, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_XDISTANCE, x + largura/2);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_YDISTANCE, y + 10);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, nomeTitulo, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, nomeTitulo, OBJPROP_TEXT, titulo);
   
   // ================= VALOR =================
   ObjectCreate(0, nomeValor, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nomeValor, OBJPROP_CORNER, PANEL_CORNER);
   ObjectSetInteger(0, nomeValor, OBJPROP_XDISTANCE, x + largura/2);
   
   // 🔥 Centro visual da área abaixo do título
   ObjectSetInteger(0, nomeValor, OBJPROP_YDISTANCE, y + (altura * 0.62));
   
   ObjectSetInteger(0, nomeValor, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, nomeValor, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, nomeValor, OBJPROP_FONTSIZE, 11);
   ObjectSetString(0, nomeValor, OBJPROP_TEXT, "0.00");
   
   
   
   
}




void CriarLinhaBody(string nome, string texto, int x)
{
   CriarLabelBody(nome, texto, x, lineY, clrWhite, 9);

   // desce automaticamente
   lineY += lineHeight;
}


//+------------------------------------------------------------------+
//| Atualização completa do Painel                                   |
//+------------------------------------------------------------------+
void AtualizarPainel()
{
   // Evita erro se ainda não criou
   if(ObjectFind(0,"LBL_PLANO") < 0)
      return;

   // =========================
   // DADOS
   // =========================
   double aberto  = OpenPositionsProfit();
   double dia     = CalcularLucroDiario();
  // double dia     = 123.56;
   double semana  = CalcularLucroSemanal();
   double mes     = g_lucroMensal;

   double total   = SaldoInicial + g_lucroAcumuladoRealizado + g_lucroAcumulado;
   
   // RESULTADO NO HEADER QUANDO COLAPSADO
if(g_panelCollapsed)
{
   string txt = "Hoje: " + DoubleToString(dia,2);

   ObjectSetString(0,"LBL_RESULTADO_DIA",OBJPROP_TEXT,txt);

   if(dia >= 0)
      ObjectSetInteger(0,"LBL_RESULTADO_DIA",OBJPROP_COLOR,clrLime);
   else
      ObjectSetInteger(0,"LBL_RESULTADO_DIA",OBJPROP_COLOR,clrTomato);
}
else
{
   ObjectSetString(0,"LBL_RESULTADO_DIA",OBJPROP_TEXT,"");
}




  
   

   // =========================
   // TEXTOS BODY
   // =========================
   ObjectSetString(0,"LBL_PLANO",  OBJPROP_TEXT, "Plano: "  + g_licensePlan);
   ObjectSetString(0,"LBL_STATUS", OBJPROP_TEXT, "Status: " + g_licenseStatus);
   ObjectSetString(0,"LBL_EXPIRA", OBJPROP_TEXT, "Expira: " + g_licenseExpiration);

   ObjectSetString(0,"LBL_ATIVO",  OBJPROP_TEXT, "Ativo: "  + _Symbol);
   ObjectSetString(0,"LBL_LOTES",  OBJPROP_TEXT, "Lotes: "  + DoubleToString(g_loteFinal,2));
   ObjectSetString(0,"LBL_HORA",   OBJPROP_TEXT, "Hora: "   + TimeToString(TimeCurrent(),TIME_SECONDS));
   
   
   
         // =============================
      // GESTÃO DE LOTES
      // =============================
      
      string s_gestao;
      string s_saldo_base;
      
      if(num_lots == 0.0)
      {
         // Gestão automática
         s_gestao = "Automática";
         s_saldo_base = DoubleToString(g_saldoBaseLotes,2);
      }
      else
      {
         // Gestão fixa
         s_gestao = "Fixa";
         s_saldo_base = "Inativo";
      }
   
   

   // Cor dinâmica do status da licença
   ObjectSetInteger(0,"LBL_STATUS",OBJPROP_COLOR,g_licenseColor);

   // =========================
   // CARDS
   // =========================
   ObjectSetString(0,"CARD_ABERTO_VAL", OBJPROP_TEXT, DoubleToString(aberto,2));
   ObjectSetString(0,"CARD_DIA_VAL",    OBJPROP_TEXT, DoubleToString(dia,2));
   ObjectSetString(0,"CARD_SEMANA_VAL", OBJPROP_TEXT, DoubleToString(semana,2));
   ObjectSetString(0,"CARD_MES_VAL",    OBJPROP_TEXT, DoubleToString(mes,2));

   // Fundo dinâmico
   ObjectSetInteger(0,"CARD_ABERTO_BG", OBJPROP_BGCOLOR, aberto >= 0 ? C'0,110,60' : C'120,0,0');
   ObjectSetInteger(0,"CARD_DIA_BG",    OBJPROP_BGCOLOR, dia    >= 0 ? C'0,110,60' : C'120,0,0');
   ObjectSetInteger(0,"CARD_SEMANA_BG", OBJPROP_BGCOLOR, semana >= 0 ? C'0,110,60' : C'120,0,0');
   ObjectSetInteger(0,"CARD_MES_BG",    OBJPROP_BGCOLOR, mes    >= 0 ? C'0,110,60' : C'120,0,0');
   
   
   
      
      
      ObjectSetString(0,"LBL_GESTAO",OBJPROP_TEXT,
                "Gestão: " + s_gestao);

      ObjectSetString(0,"LBL_SALDO_BASE",OBJPROP_TEXT,
                "Saldo Base: " + s_saldo_base);
   
   
   
   
         
   
   
   
   
   

   ChartRedraw();
}





void RemoverPainel()
{
   string objetos[] =
   {
      PANEL_NAME,
      PANEL_HEADER_NAME,
      PANEL_BODY_NAME,

      "SLYBOT_LOGO",
      "LBL_TITLE",
      "LBL_RESULTADO_DIA",

      

      BTN_COLLAPSE,

      "BTN_POWER_BG",
      "BTN_POWER_TXT",

      "LBL_PLANO",
      "LBL_STATUS",
      "LBL_EXPIRA",
      "LBL_ATIVO",
      "LBL_LOTES",
      "LBL_GESTAO",
      "LBL_SALDO_BASE",
      "LBL_HORA",

      "CARD_ABERTO_BG",
      "CARD_ABERTO_TIT",
      "CARD_ABERTO_VAL",

      "CARD_DIA_BG",
      "CARD_DIA_TIT",
      "CARD_DIA_VAL",

      "CARD_SEMANA_BG",
      "CARD_SEMANA_TIT",
      "CARD_SEMANA_VAL",

      "CARD_MES_BG",
      "CARD_MES_TIT",
      "CARD_MES_VAL",

      "BTN_CLOSE_ALL_BG",
      "BTN_CLOSE_ALL_TXT"
   };

   for(int i=0;i<ArraySize(objetos);i++)
   {
      if(ObjectFind(0,objetos[i]) >= 0)
         ObjectDelete(0,objetos[i]);
   }
}




double CalcularLucroDiario()
{
   double lucro = 0.0;

   MqlDateTime agora;
   TimeToStruct(TimeCurrent(), agora);

   MqlDateTime inicio = agora;
   inicio.hour = 0;
   inicio.min  = 0;
   inicio.sec  = 0;

   datetime inicioDia = StructToTime(inicio);

   if(!HistorySelect(inicioDia, TimeCurrent()))
      return 0.0;

   int total = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);

      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == magicNumber &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         lucro += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }

   return lucro;
}



//+------------------------------------------------------------------+
//| Lucro da semana atual (MQL5 correto)                             |
//+------------------------------------------------------------------+
double CalcularLucroSemanal()
{
   double lucro = 0.0;

   datetime agora = TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(agora, dt);

   // dt.day_of_week -> 0 = domingo, 1 = segunda ...
   datetime inicioSemana = agora - (dt.day_of_week * 86400);

   if(!HistorySelect(inicioSemana, agora))
      return 0.0;

   int total = HistoryDealsTotal();

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);

      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == magicNumber &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         lucro += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }

   return lucro;
}

//vitalicio - 34jK3eE8r4LNgB8RuzZWieOxNqTRvTqu
//anual - zCw9UZqOt2ZHFN0REK2vTs7MedHQueGw