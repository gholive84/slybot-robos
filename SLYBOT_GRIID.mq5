//+------------------------------------------------------------------+
//|                           Gradiente_MANUS_V1.5_CORRIGIDO.mq5   |
//|                      Desenvolvido por gholive@gmail.com         |
//|                      VERSÃO CORRIGIDA - Ordens A Favor          |
//+------------------------------------------------------------------+
#property copyright "Desenvolvido por gholive@gmail.com - VERSÃO CORRIGIDA"
#property link      ""
#property version   "1.53"
#property description "Robô de Gradiente Dinâmico V1.5 CORRIGIDO - Grid a favor com reset - MODIFICADO PARA CONTA HEDGE - FIX: Trigger comparação int/string corrigida"
#property strict

// Inclusão de bibliotecas necessárias
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\OrderInfo.mqh>

// Enumerações
enum ENUM_GRID_TYPE {
   GRID_FIXED = 0,    // Grid Fixo
   GRID_DYNAMIC = 1   // Grid Dinâmico (Contra e a Favor)
};

enum ENUM_TRIGGER_TYPE {
   TRIGGER_STATS = 0
};

// Parâmetros de entrada
input string InpComment = "Gradiente MANUS V1.5"; // Comentário
input int InpMagicNumber = 123467;                 // Número Mágico

// Parâmetros de Proteção
input double InpStopLoss = 100000.0;       // Stop Loss da operação gatilho (pontos, 0 = desativado)
input double InpTakeProfit = 100000.0;     // Take Profit da operação gatilho (pontos, 0 = desativado)
input double InpDailyLossLimit = 1000.0;   // Limite de Loss Diário (R$)
input double InpDailyProfitLimit = 2000.0; // Limite de Gain Diário (R$)

// Parâmetros do Grid
input ENUM_GRID_TYPE InpGridType = GRID_DYNAMIC; // Tipo de Grid
input double InpGridInterval = 20000.0;    // Intervalo entre ordens do grid (pontos)
input int InpGridLevels = 5;               // Quantidade de níveis do grid (contra)
input double InpContractCost = 0.20;       // Custo por contrato (R$)
input bool InpShowGridLines = true;        // Mostrar linhas do grid no gráfico

// Parâmetros de Horário
input string InpStartTime = "09:00";       // Horário de início
input string InpEndTime = "17:00";         // Horário de término
input string InpCloseTime = "17:30";       // Horário para fechar posições
input bool InpSwingTradeMode = false;      // Modo Swing Trade (ignora horários de operação)

// Parâmetros de Volume
input double InpLotSize = 1.0;             // Tamanho do lote fixo
input double InpLotgatilho = 1.0;          // Tamanho do lote gatilho

// Parâmetros de Gatilho de Percentagem
input bool         tendencia               = true;          // True = Favor da tendencia, false = Contra tendência
input double       perc_alta               = 1.0;           // % de alta
input double       perc_queda              = 1.0;           // % de queda
input ENUM_TIMEFRAMES mm_tempo_grafico     = PERIOD_CURRENT; // Tempo gráfico

// Parâmetros de Gatilho
input ENUM_TRIGGER_TYPE InpTriggerType = TRIGGER_STATS; // Tipo de Gatilho

// Parâmetros do Painel Visual
input color InpPanelColor = clrDarkBlue;   // Cor de fundo do painel
input color InpTextColor = clrWhite;       // Cor do texto do painel
input int InpPanelCorner = CORNER_LEFT_UPPER; // Canto do painel


//--- Variáveis internas de mercado
double g_fechaAnterior, g_precoEntradaC, g_precoEntradaV, g_precoAtual, g_fechamentoBarra, g_percentualQueda, g_percentualAlta, g_aberturaDia, g_loteFinal;
int g_currentTime;      // Horário atual no formato HHMM (ex: 930 para 09:30)
int g_startTimeHHMM;    // InpStartTime convertido para HHMM int (ex: 900 para "09:00")

// Variáveis globais
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;
COrderInfo orderInfo;
int bandHandle;
double dailyProfit = 0.0;
double weeklyProfit = 0.0;
double monthlyProfit = 0.0;
bool isNewDay = true;
bool isNewWeek = true;
bool isNewMonth = true;
datetime lastBarTime = 0;
bool robotEnabled = true;
int totalTrades = 0;
datetime lastTriggerTime = 0;
bool triggerPositionOpen = false;
double triggerEntryPrice = 0.0;
ulong triggerPositionTicket = 0;
ENUM_POSITION_TYPE triggerPositionType;
string triggerTimeStr;
double fiboLevels[];
bool panelMinimized = false;

// Variáveis para Fibonacci
double fiboHighPrice = 0;
double fiboLowPrice = DBL_MAX;
datetime fiboHighTime = 0;
datetime fiboLowTime = 0;
bool fiboLinesDrawn = false;

// Variáveis para modo Manual
ulong manualBuyOrderTicket = 0;
ulong manualSellOrderTicket = 0;

// Variáveis para debug
bool debugMode = true;
datetime lastDebugTime = 0;

// --- Variáveis do Grid ---
double gridLevelsContraBuy[];
double gridLevelsContraSell[];
bool gridLevelContraUsedBuy[];
bool gridLevelContraUsedSell[];

// --- Variáveis do Grid a Favor ---
ulong gridAFavorOrderTicketBuy = 0;
ulong gridAFavorOrderTicketSell = 0;
double gridAFavorCurrentLevelBuy = 0;
double gridAFavorCurrentLevelSell = 0;
bool gridAFavorActiveGridBuy = false;
bool gridAFavorActiveGridSell = false;
double gridAFavorLastPriceBuy = 0;
double gridAFavorLastPriceSell = 0;

// --- Variáveis para Limite Diário ---
bool dailyLimitReached = false;

// --- Variáveis para rastreamento de ordens do grid ---
struct GRID_ORDER {
   ulong ticket;
   double price;
   double takeProfit;
   string comment;
   bool isActive;
};

GRID_ORDER gridOrdersContraBuy[];
GRID_ORDER gridOrdersContraSell[];
bool gridInitialized = false;

// Enumeração para status de horário
enum ENUM_TIME_STATUS {
   TIME_INACTIVE,
   TIME_ACTIVE,
   TIME_CLOSE
};

// Estrutura para armazenar informações do painel
struct PANEL_INFO {
   string symbol;
   double currentPrice;
   double dailyProfit;
   double weeklyProfit;
   double monthlyProfit;
   int totalTrades;
   int activeTrades;
   string gridStatus;
   string triggerStatus;
   string manualOrderStatus;
};

PANEL_INFO panelInfo;

// Nomes dos objetos do painel
string panelName = "GradientePanel";
string panelMinimizeButton = "GradientePanelMinimize";
string panelBuyButton = "GradientePanelBuy";
string panelSellButton = "GradientePanelSell";
string panelCloseButton = "GradientePanelClose";


//+------------------------------------------------------------------+
//| Função para obter preço atual com validação e fallback           |
//+------------------------------------------------------------------+
double GetCurrentPrice() {
   double price = symbolInfo.Last();
   if(price <= 0) {
      price = symbolInfo.Bid();
      if(price <= 0) price = symbolInfo.Ask();
   }
   if(price <= 0) {
      if(symbolInfo.RefreshRates()) {
         price = symbolInfo.Last();
         if(price <= 0) {
            price = symbolInfo.Bid();
            if(price <= 0) price = symbolInfo.Ask();
         }
      }
   }
   if(price <= 0) {
      PrintFormat("ERRO CRÍTICO: Não foi possível obter preço válido para %s. Last=%.5f, Bid=%.5f, Ask=%.5f",
                  _Symbol, symbolInfo.Last(), symbolInfo.Bid(), symbolInfo.Ask());
   }
   return price;
}

//+------------------------------------------------------------------+
//| Função para remover espaços em branco no início e fim da string  |
//+------------------------------------------------------------------+
string TrimString(string str) {
   while(StringLen(str) > 0 && StringGetCharacter(str, 0) == ' ')
      str = StringSubstr(str, 1);
   while(StringLen(str) > 0 && StringGetCharacter(str, StringLen(str) - 1) == ' ')
      str = StringSubstr(str, 0, StringLen(str) - 1);
   return str;
}

//+------------------------------------------------------------------+
//| Função para converter string de horário para segundos            |
//+------------------------------------------------------------------+
int StringToTimeSeconds(string timeStr) {
   timeStr = TrimString(timeStr);
   if(StringLen(timeStr) != 5 || StringGetCharacter(timeStr, 2) != ':') {
      Print("Formato de horário inválido! Por favor, use HH:MM.");
      return -1;
   }
   int hours = (int)StringToInteger(StringSubstr(timeStr, 0, 2));
   int minutes = (int)StringToInteger(StringSubstr(timeStr, 3, 2));
   if(hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      Print("Valores de horário inválidos! Horas: 0-23, Minutos: 0-59");
      return -1;
   }
   return hours * 3600 + minutes * 60;
}

//+------------------------------------------------------------------+
//| NOVA FUNÇÃO: Converter string "HH:MM" para int HHMM             |
//| Ex: "09:00" -> 900, "17:30" -> 1730                             |
//+------------------------------------------------------------------+
int TimeStringToHHMM(string timeStr) {
   timeStr = TrimString(timeStr);
   if(StringLen(timeStr) != 5 || StringGetCharacter(timeStr, 2) != ':') {
      Print("Formato de horário inválido em TimeStringToHHMM: ", timeStr);
      return -1;
   }
   int hours   = (int)StringToInteger(StringSubstr(timeStr, 0, 2));
   int minutes = (int)StringToInteger(StringSubstr(timeStr, 3, 2));
   if(hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
      Print("Valores de horário inválidos em TimeStringToHHMM: ", timeStr);
      return -1;
   }
   return hours * 100 + minutes;
}

//+------------------------------------------------------------------+
//| Função para verificar se o horário atual está dentro do intervalo|
//+------------------------------------------------------------------+
bool IsTimeInRange(string startTimeStr, string endTimeStr) {
   if(InpSwingTradeMode) return true;
   int startSeconds = StringToTimeSeconds(startTimeStr);
   int endSeconds   = StringToTimeSeconds(endTimeStr);
   if(startSeconds == -1 || endSeconds == -1) return false;
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currentSeconds = now.hour * 3600 + now.min * 60 + now.sec;
   return (currentSeconds >= startSeconds && currentSeconds <= endSeconds);
}

//+------------------------------------------------------------------+
//| Função para verificar se o horário atual é igual ao especificado |
//+------------------------------------------------------------------+
bool IsTimeEqual(string timeStr) {
   if(InpSwingTradeMode) return false;
   int timeSeconds = StringToTimeSeconds(timeStr);
   if(timeSeconds == -1) return false;
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currentSeconds = now.hour * 3600 + now.min * 60;
   return (currentSeconds >= timeSeconds && currentSeconds < timeSeconds + 60);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
   PrintFormat("--- DIAGNÓSTICO TP --- Verificando StopLevel para %s...", _Symbol);
   long stopLevelLong = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopLevelLong < 0) {
       Print("--- DIAGNÓSTICO TP --- Erro ao obter StopLevel: ", GetLastError());
   } else {
       double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
       if(pointValue <= 0) {
          Print("--- DIAGNÓSTICO TP --- Erro ao obter o valor do ponto para o símbolo.");
          pointValue = _Point;
       }
       PrintFormat("--- DIAGNÓSTICO TP --- StopLevel para %s: %d pontos (valor ponto: %.8f)",
                   _Symbol, stopLevelLong, pointValue);
   }

   if(!symbolInfo.Name(_Symbol)) {
      Print("Falha ao configurar o símbolo: ", _Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);

   ArrayResize(gridLevelsContraBuy,  InpGridLevels);
   ArrayResize(gridLevelsContraSell, InpGridLevels);
   ArrayResize(gridLevelContraUsedBuy,  InpGridLevels);
   ArrayResize(gridLevelContraUsedSell, InpGridLevels);
   ArrayFill(gridLevelContraUsedBuy,  0, InpGridLevels, false);
   ArrayFill(gridLevelContraUsedSell, 0, InpGridLevels, false);
   ArrayResize(gridOrdersContraBuy,  InpGridLevels);
   ArrayResize(gridOrdersContraSell, InpGridLevels);

   // *** CORREÇÃO: Pré-calcular g_startTimeHHMM uma vez na inicialização ***
   g_startTimeHHMM = TimeStringToHHMM(InpStartTime);
   if(g_startTimeHHMM == -1) {
      Print("ERRO: Horário de início inválido: ", InpStartTime, ". Usando 900 (09:00) como padrão.");
      g_startTimeHHMM = 900;
   }
   PrintFormat("Horário de início configurado: %s -> HHMM=%d", InpStartTime, g_startTimeHHMM);

   // *** Inicializar dados de mercado imediatamente para evitar valores zerados ***
   AtualizarDadosDoMercado();
   CalcularPrecosDeEntrada();

   CreatePanel();
   CalculateDailyProfit();
   CalculateWeeklyProfit();
   CalculateMonthlyProfit();

   if(InpSwingTradeMode)
      Print("MODO SWING TRADE ATIVADO - Horários de operação serão ignorados!");

   Print("Gradiente MANUS V1.5 CORRIGIDO inicializado com sucesso! (v1.53 - Fix trigger)");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   if(bandHandle != INVALID_HANDLE) IndicatorRelease(bandHandle);
   DeletePanel();
   DeleteGridLines();
   if(manualBuyOrderTicket > 0)        trade.OrderDelete(manualBuyOrderTicket);
   if(manualSellOrderTicket > 0)       trade.OrderDelete(manualSellOrderTicket);
   if(gridAFavorOrderTicketBuy > 0)    trade.OrderDelete(gridAFavorOrderTicketBuy);
   if(gridAFavorOrderTicketSell > 0)   trade.OrderDelete(gridAFavorOrderTicketSell);
   Print("Gradiente MANUS V1.5 CORRIGIDO finalizado. Motivo: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   if(!robotEnabled) return;

   GerenciarHorarios();

   if(NovoCandle()) {
      AtualizarDadosDoMercado();
      CalcularPrecosDeEntrada();
      DesenharLinhas();
   }

   // *** CORREÇÃO: Garantir que preços estejam calculados mesmo sem novo candle ***
   if(g_precoEntradaC <= 0 || g_precoEntradaV <= 0) {
      AtualizarDadosDoMercado();
      CalcularPrecosDeEntrada();
   }

   if(!symbolInfo.RefreshRates()) {
      Print("Falha ao atualizar as taxas do símbolo");
      return;
   }

   // Debug a cada 5 segundos
   if(debugMode) {
      datetime currentTime = TimeCurrent();
      if(currentTime - lastDebugTime >= 5) {
         lastDebugTime = currentTime;
         DebugPrint();
      }
   }

   CheckNewTimeframes();
   CalculateDailyProfit();
   CalculateWeeklyProfit();
   CalculateMonthlyProfit();

   if(dailyLimitReached) {
      UpdatePanel(TIME_INACTIVE);
      return;
   }
   if(CheckDailyLimits()) {
      UpdatePanel(TIME_INACTIVE);
      return;
   }

   ENUM_TIME_STATUS timeStatus = CheckTimeStatus();
   UpdatePanel(timeStatus);

   if(!InpSwingTradeMode && timeStatus == TIME_CLOSE) {
      CloseAllPositions();
      return;
   }

   ManagePositions();

   if(!InpSwingTradeMode && timeStatus != TIME_ACTIVE) return;

   CheckGridOrdersExecution();

   if(!triggerPositionOpen) {
      CheckTriggers();
   }

   if(triggerPositionOpen) {
      ManageGrid();
      if(InpGridType == GRID_DYNAMIC) {
         UpdateAFavorLimitOrder();
      }
   }
}


//+------------------------------------------------------------------+
//| Função de debug para imprimir informações importantes            |
//+------------------------------------------------------------------+
void DebugPrint() {
   double currentPrice = GetCurrentPrice();

   Print("=== DEBUG INFO v1.53 CORRIGIDO ===");
   PrintFormat("Preço atual: %.2f", currentPrice);
   Print("Trigger posição aberta: ", triggerPositionOpen);
   Print("Modo Swing Trade: ", InpSwingTradeMode ? "ATIVO" : "INATIVO");

   // *** NOVO: Mostrar valores críticos do trigger ***
   PrintFormat("TRIGGER VALS -> g_currentTime=%d, g_startTimeHHMM=%d, aberturaDia=%.2f, entradaC=%.2f, entradaV=%.2f, fechamentoBarra=%.2f",
               g_currentTime, g_startTimeHHMM, g_aberturaDia, g_precoEntradaC, g_precoEntradaV, g_fechamentoBarra);

   if(triggerPositionOpen) {
      Print("Tipo de posição trigger ORIGINAL: ", EnumToString(triggerPositionType));
      PrintFormat("Preço de referência ATUAL do grid: %.2f", triggerEntryPrice);
      Print("Ticket da posição trigger ORIGINAL: ", triggerPositionTicket);

      if(triggerPositionType == POSITION_TYPE_BUY) {
         for(int i = 0; i < InpGridLevels; i++)
            PrintFormat("Grid Contra Buy Nível %d: %.2f, Usado: %s", i, gridLevelsContraBuy[i], gridLevelContraUsedBuy[i] ? "SIM" : "NÃO");
         PrintFormat("Grid A Favor Buy (pendente): %.2f, Ativo: %s, Ticket: %d",
                     gridAFavorCurrentLevelBuy, gridAFavorActiveGridBuy ? "SIM" : "NÃO", gridAFavorOrderTicketBuy);
      } else {
         for(int i = 0; i < InpGridLevels; i++)
            PrintFormat("Grid Contra Sell Nível %d: %.2f, Usado: %s", i, gridLevelsContraSell[i], gridLevelContraUsedSell[i] ? "SIM" : "NÃO");
         PrintFormat("Grid A Favor Sell (pendente): %.2f, Ativo: %s, Ticket: %d",
                     gridAFavorCurrentLevelSell, gridAFavorActiveGridSell ? "SIM" : "NÃO", gridAFavorOrderTicketSell);
      }
   }

   int posCount = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber) {
            posCount++;
            PrintFormat("Posição #%d: Ticket=%d, Tipo=%s, Preço=%.2f, TP=%.2f, SL=%.2f, Comentário=%s",
                        posCount, positionInfo.Ticket(),
                        EnumToString((ENUM_POSITION_TYPE)positionInfo.PositionType()),
                        positionInfo.PriceOpen(), positionInfo.TakeProfit(),
                        positionInfo.StopLoss(), positionInfo.Comment());
         }
      }
   }

   Print("=== FIM DEBUG ===");
}

//+------------------------------------------------------------------+
//| Função para verificar execução de ordens do grid e resetar flags |
//+------------------------------------------------------------------+
void CheckGridOrdersExecution() {
   for(int i = 0; i < InpGridLevels; i++) {
      if(gridOrdersContraBuy[i].isActive) {
         bool positionExists = false;
         if(positionInfo.SelectByTicket(gridOrdersContraBuy[i].ticket))
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
               positionExists = true;
         if(!positionExists) {
            gridLevelContraUsedBuy[i]      = false;
            gridOrdersContraBuy[i].isActive = false;
            PrintFormat("Nível do grid contra (compra) resetado: Nível %d, Preço: %.2f", i, gridLevelsContraBuy[i]);
            if(InpShowGridLines) UpdateGridLines();
         }
      }
   }
   for(int i = 0; i < InpGridLevels; i++) {
      if(gridOrdersContraSell[i].isActive) {
         bool positionExists = false;
         if(positionInfo.SelectByTicket(gridOrdersContraSell[i].ticket))
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
               positionExists = true;
         if(!positionExists) {
            gridLevelContraUsedSell[i]      = false;
            gridOrdersContraSell[i].isActive = false;
            PrintFormat("Nível do grid contra (venda) resetado: Nível %d, Preço: %.2f", i, gridLevelsContraSell[i]);
            if(InpShowGridLines) UpdateGridLines();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Função para verificar novos timeframes (dia, semana, mês)        |
//+------------------------------------------------------------------+
void CheckNewTimeframes() {
   static int lastDay   = -1;
   static int lastWeek  = -1;
   static int lastMonth = -1;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   if(now.day != lastDay) {
      isNewDay = true;
      lastDay  = now.day;
      if(dailyLimitReached) {
         dailyLimitReached = false;
         Print("Novo dia: Limite diário resetado");
      }
   } else {
      isNewDay = false;
   }

   int currentWeekDay = now.day_of_week;
   if(lastWeek == -1) lastWeek = currentWeekDay;
   isNewWeek = (currentWeekDay < lastWeek);
   lastWeek  = currentWeekDay;

   if(now.mon != lastMonth) {
      isNewMonth = true;
      lastMonth  = now.mon;
   } else {
      isNewMonth = false;
   }
}

//+------------------------------------------------------------------+
//| Função para calcular o lucro diário                               |
//+------------------------------------------------------------------+
void CalculateDailyProfit() {
   if(isNewDay) dailyProfit = 0.0;

   double currentFloatingProfit = 0.0;
   MqlDateTime _now_ts;
   TimeToStruct(TimeCurrent(), _now_ts);
   _now_ts.hour = 0; _now_ts.min = 0; _now_ts.sec = 0;
   datetime todayStart = StructToTime(_now_ts);

   for(int i = 0; i < PositionsTotal(); i++) {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            currentFloatingProfit += positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
   }

   double realizedProfitToday = 0;
   if(HistorySelect(todayStart, TimeCurrent())) {
      for(int i = 0; i < HistoryDealsTotal(); i++) {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == InpMagicNumber &&
            HistoryDealGetString(dealTicket, DEAL_SYMBOL) == _Symbol &&
            (HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN ||
             HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT))
         {
            realizedProfitToday += HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                                   HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                                   HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         }
      }
   }
   dailyProfit = realizedProfitToday + currentFloatingProfit;
}

void CalculateWeeklyProfit() {
   if(isNewWeek) weeklyProfit = 0.0;
   weeklyProfit = dailyProfit;
}

void CalculateMonthlyProfit() {
   if(isNewMonth) monthlyProfit = 0.0;
   monthlyProfit = dailyProfit;
}

//+------------------------------------------------------------------+
//| Função para verificar os limites diários                          |
//+------------------------------------------------------------------+
bool CheckDailyLimits() {
   if(dailyLimitReached) return true;
   if(InpDailyLossLimit > 0 && dailyProfit <= -InpDailyLossLimit) {
      PrintFormat("Limite de loss diário (R$ %.2f) atingido! Lucro atual: R$ %.2f", InpDailyLossLimit, dailyProfit);
      CloseAllPositions();
      dailyLimitReached = true;
      return true;
   }
   if(InpDailyProfitLimit > 0 && dailyProfit >= InpDailyProfitLimit) {
      PrintFormat("Limite de gain diário (R$ %.2f) atingido! Lucro atual: R$ %.2f", InpDailyProfitLimit, dailyProfit);
      CloseAllPositions();
      dailyLimitReached = true;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Função para verificar o status do horário de operação             |
//+------------------------------------------------------------------+
ENUM_TIME_STATUS CheckTimeStatus() {
   if(InpSwingTradeMode) return TIME_ACTIVE;
   if(IsTimeEqual(InpCloseTime)) return TIME_CLOSE;
   if(IsTimeInRange(InpStartTime, InpEndTime)) return TIME_ACTIVE;
   return TIME_INACTIVE;
}

//+------------------------------------------------------------------+
//| Função para fechar todas as posições e ordens do robô             |
//+------------------------------------------------------------------+
void CloseAllPositions() {
   Print("Fechando todas as posições e cancelando ordens pendentes...");
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(orderInfo.SelectByIndex(i))
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
            if(!trade.OrderDelete(orderInfo.Ticket()))
               Print("Erro ao deletar ordem pendente: ", orderInfo.Ticket(), ", Erro: ", trade.ResultRetcode());
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            if(!trade.PositionClose(positionInfo.Ticket()))
               Print("Erro ao fechar posição: ", positionInfo.Ticket(), ", Erro: ", trade.ResultRetcode());
   }

   triggerPositionOpen    = false;
   triggerPositionTicket  = 0;
   triggerEntryPrice      = 0.0;

   gridAFavorOrderTicketBuy    = 0;
   gridAFavorOrderTicketSell   = 0;
   gridAFavorCurrentLevelBuy   = 0;
   gridAFavorCurrentLevelSell  = 0;
   gridAFavorActiveGridBuy     = false;
   gridAFavorActiveGridSell    = false;

   ArrayFill(gridLevelContraUsedBuy,  0, InpGridLevels, false);
   ArrayFill(gridLevelContraUsedSell, 0, InpGridLevels, false);
   ArrayFree(gridOrdersContraBuy);
   ArrayFree(gridOrdersContraSell);
   ArrayResize(gridOrdersContraBuy,  InpGridLevels);
   ArrayResize(gridOrdersContraSell, InpGridLevels);

   DeleteGridLines();
   gridInitialized = false;
   Print("Fechamento completo e reset de estado concluídos.");
}

//+------------------------------------------------------------------+
//| Função para gerenciar posições existentes                         |
//+------------------------------------------------------------------+
void ManagePositions() {
   double currentPrice = GetCurrentPrice();
   if(currentPrice <= 0) {
      PrintFormat("ERRO: Preço atual inválido (%.5f) em ManagePositions.", currentPrice);
      return;
   }

   bool gatilhoOriginalFound = false;

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber) {
            ulong currentTicket           = positionInfo.Ticket();
            ENUM_POSITION_TYPE posType    = positionInfo.PositionType();
            double posOpenPrice           = positionInfo.PriceOpen();
            double posTakeProfit          = positionInfo.TakeProfit();

            if(currentTicket == triggerPositionTicket) {
               gatilhoOriginalFound = true;

               if(InpTakeProfit > 0 && posTakeProfit > 0) {
                  bool tpAtingido = false;
                  if(posType == POSITION_TYPE_BUY  && currentPrice >= posTakeProfit) tpAtingido = true;
                  if(posType == POSITION_TYPE_SELL && currentPrice <= posTakeProfit) tpAtingido = true;

                  if(tpAtingido) {
                     PrintFormat("✅ Take Profit da ordem gatilho atingido! Fechando todas. TP: %.2f, Preço: %.2f",
                                 posTakeProfit, currentPrice);
                     CloseAllPositions();
                     return;
                  }
               }

               if(InpStopLoss > 0) {
                  if(posType == POSITION_TYPE_BUY  && currentPrice <= posOpenPrice - InpStopLoss * _Point) {
                     PrintFormat("Stop Loss GERAL atingido (BUY). Preço: %.2f, Gatilho: %.2f", currentPrice, posOpenPrice);
                     CloseAllPositions();
                     return;
                  }
                  if(posType == POSITION_TYPE_SELL && currentPrice >= posOpenPrice + InpStopLoss * _Point) {
                     PrintFormat("Stop Loss GERAL atingido (SELL). Preço: %.2f, Gatilho: %.2f", currentPrice, posOpenPrice);
                     CloseAllPositions();
                     return;
                  }
               }
            }
         }
      }
   }

   if(!gatilhoOriginalFound && triggerPositionOpen) {
      Print("Posição de gatilho ORIGINAL não encontrada. Resetando estado geral do robô.");
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Função para calcular SL/TP respeitando SYMBOL_TRADE_STOPS_LEVEL  |
//+------------------------------------------------------------------+
bool CalculateStopLevels(ENUM_POSITION_TYPE posType, double currentPrice,
                         double slPoints, double tpPoints,
                         double &stopLoss, double &takeProfit) {
   stopLoss   = 0;
   takeProfit = 0;

   if(currentPrice <= 0) {
      PrintFormat("ERRO: Preço atual inválido (%.5f). Não é possível calcular SL/TP.", currentPrice);
      return false;
   }
   if(slPoints <= 0 && tpPoints <= 0) return true;

   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevel    = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopLevel * point;

   double slDistance = slPoints * point;
   double tpDistance = tpPoints * point;

   if(slPoints > 0 && slDistance < minDistance) slDistance = minDistance + (10 * point);
   if(tpPoints > 0 && tpDistance < minDistance) tpDistance = minDistance + (10 * point);

   if(posType == POSITION_TYPE_BUY) {
      if(slPoints > 0) stopLoss   = NormalizeDouble(currentPrice - slDistance, _Digits);
      if(tpPoints > 0) takeProfit = NormalizeDouble(currentPrice + tpDistance, _Digits);
   } else {
      if(slPoints > 0) stopLoss   = NormalizeDouble(currentPrice + slDistance, _Digits);
      if(tpPoints > 0) takeProfit = NormalizeDouble(currentPrice - tpDistance, _Digits);
   }

   if(stopLoss > 0 && MathAbs(currentPrice - stopLoss) < minDistance) stopLoss = 0;
   if(takeProfit > 0 && MathAbs(currentPrice - takeProfit) < minDistance) takeProfit = 0;

   PrintFormat("SL/TP calculado -> Preço: %.2f, SL: %.2f, TP: %.2f", currentPrice, stopLoss, takeProfit);
   return true;
}

//+------------------------------------------------------------------+
//| Função para abrir posição gatilho                                 |
//+------------------------------------------------------------------+
void OpenTriggerPosition(ENUM_POSITION_TYPE posType) {
   if(triggerPositionOpen) {
      Print("Tentativa de abrir nova posição gatilho enquanto uma já está aberta. Ignorando.");
      return;
   }
   if(dailyLimitReached) {
      Print("Limite diário atingido. Bloqueando abertura de nova posição gatilho.");
      return;
   }

   string comment    = "GATILHO_" + EnumToString(InpTriggerType);
   bool result       = false;
   double stopLoss   = 0;
   double takeProfit = 0;
   double currentPrice = GetCurrentPrice();

   if(currentPrice <= 0) {
      PrintFormat("❌ ERRO CRÍTICO: Preço inválido para %s. Abortando abertura.", _Symbol);
      return;
   }

   if(!CalculateStopLevels(posType, currentPrice, InpStopLoss, InpTakeProfit, stopLoss, takeProfit)) {
      stopLoss = 0; takeProfit = 0;
   }

   if(posType == POSITION_TYPE_BUY)
      result = trade.Buy(InpLotgatilho, _Symbol, 0, stopLoss, takeProfit, comment);
   else
      result = trade.Sell(InpLotgatilho, _Symbol, 0, stopLoss, takeProfit, comment);

   if(result) {
      triggerPositionOpen   = true;
      triggerPositionType   = posType;
      triggerPositionTicket = trade.ResultOrder();
      triggerEntryPrice     = trade.ResultPrice();
      totalTrades++;
      PrintFormat("✅ Posição gatilho %s aberta: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                  EnumToString(posType), triggerPositionTicket, triggerEntryPrice, stopLoss, takeProfit);
      gridInitialized = false;
   } else {
      PrintFormat("❌ Erro ao abrir posição gatilho %s: Erro=%d - %s",
                  EnumToString(posType), trade.ResultRetcode(), trade.ResultRetcodeDescription());

      if(trade.ResultRetcode() == 10016 || trade.ResultRetcode() == 10017) {
         Print("Tentando abrir posição sem SL/TP...");
         if(posType == POSITION_TYPE_BUY)
            result = trade.Buy(InpLotgatilho, _Symbol, 0, 0, 0, comment);
         else
            result = trade.Sell(InpLotgatilho, _Symbol, 0, 0, 0, comment);

         if(result) {
            triggerPositionOpen   = true;
            triggerPositionType   = posType;
            triggerPositionTicket = trade.ResultOrder();
            triggerEntryPrice     = trade.ResultPrice();
            totalTrades++;
            PrintFormat("⚠️ Posição gatilho %s aberta SEM proteção: Ticket=%d, Preço=%.2f",
                        EnumToString(posType), triggerPositionTicket, triggerEntryPrice);
            gridInitialized = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Função para inicializar o grid                                    |
//+------------------------------------------------------------------+
void InitializeGrid() {
   if(!triggerPositionOpen) return;
   PrintFormat("Inicializando/Reinicializando grid com referência: %.2f", triggerEntryPrice);

   if(triggerPositionType == POSITION_TYPE_BUY) {
      for(int i = 0; i < InpGridLevels; i++) {
         gridLevelsContraBuy[i]      = triggerEntryPrice - (i + 1) * InpGridInterval * _Point;
         gridLevelContraUsedBuy[i]   = false;
         gridOrdersContraBuy[i].isActive = false;
      }
      gridAFavorLastPriceBuy    = triggerEntryPrice;
      gridAFavorCurrentLevelBuy = 0;
      gridAFavorActiveGridBuy   = false;
      gridAFavorOrderTicketBuy  = 0;
   } else {
      for(int i = 0; i < InpGridLevels; i++) {
         gridLevelsContraSell[i]     = triggerEntryPrice + (i + 1) * InpGridInterval * _Point;
         gridLevelContraUsedSell[i]  = false;
         gridOrdersContraSell[i].isActive = false;
      }
      gridAFavorLastPriceSell    = triggerEntryPrice;
      gridAFavorCurrentLevelSell = 0;
      gridAFavorActiveGridSell   = false;
      gridAFavorOrderTicketSell  = 0;
   }

   if(InpShowGridLines) DrawGridLines();
   gridInitialized = true;
}

//+------------------------------------------------------------------+
//| Função para gerenciar o grid CONTRA                               |
//+------------------------------------------------------------------+
void ManageGrid() {
   if(!triggerPositionOpen) return;

   double currentPrice = GetCurrentPrice();
   if(currentPrice <= 0) {
      PrintFormat("ERRO: Preço inválido em ManageGrid.");
      return;
   }

   if(!gridInitialized) InitializeGrid();

   if(triggerPositionType == POSITION_TYPE_BUY) {
      for(int i = 0; i < InpGridLevels; i++) {
         if(currentPrice <= gridLevelsContraBuy[i] && !gridLevelContraUsedBuy[i]) {
            if(gridOrdersContraBuy[i].isActive) continue;
            string comment = "GRID_CONTRA_BUY_" + IntegerToString(i);
            double stopLoss = 0, takeProfit = 0;
            double tpPoints = InpGridInterval;
            double slPoints = InpStopLoss;
            if(positionInfo.SelectByTicket(triggerPositionTicket) && positionInfo.StopLoss() > 0)
               slPoints = MathAbs(currentPrice - positionInfo.StopLoss()) / _Point;

            if(CalculateStopLevels(POSITION_TYPE_BUY, currentPrice, slPoints, tpPoints, stopLoss, takeProfit)) {
               if(trade.Buy(InpLotSize, _Symbol, 0, stopLoss, takeProfit, comment)) {
                  ulong ticket = trade.ResultOrder();
                  PrintFormat("✅ Grid Contra BUY_%d aberto: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                              i, ticket, trade.ResultPrice(), stopLoss, takeProfit);
                  gridLevelContraUsedBuy[i]          = true;
                  gridOrdersContraBuy[i].ticket      = ticket;
                  gridOrdersContraBuy[i].price       = trade.ResultPrice();
                  gridOrdersContraBuy[i].takeProfit  = takeProfit;
                  gridOrdersContraBuy[i].comment     = comment;
                  gridOrdersContraBuy[i].isActive    = true;
                  if(InpShowGridLines) UpdateGridLines();
               } else {
                  PrintFormat("❌ Erro Grid Contra BUY_%d: %d - %s", i, trade.ResultRetcode(), trade.ResultRetcodeDescription());
                  if(trade.ResultRetcode() == 10016 || trade.ResultRetcode() == 10017) {
                     if(trade.Buy(InpLotSize, _Symbol, 0, 0, 0, comment)) {
                        ulong ticket = trade.ResultOrder();
                        gridLevelContraUsedBuy[i]       = true;
                        gridOrdersContraBuy[i].ticket   = ticket;
                        gridOrdersContraBuy[i].price    = trade.ResultPrice();
                        gridOrdersContraBuy[i].takeProfit = 0;
                        gridOrdersContraBuy[i].comment  = comment;
                        gridOrdersContraBuy[i].isActive = true;
                        if(InpShowGridLines) UpdateGridLines();
                     }
                  }
               }
            }
         }
      }
   } else {
      for(int i = 0; i < InpGridLevels; i++) {
         if(currentPrice >= gridLevelsContraSell[i] && !gridLevelContraUsedSell[i]) {
            if(gridOrdersContraSell[i].isActive) continue;
            string comment = "GRID_CONTRA_SELL_" + IntegerToString(i);
            double stopLoss = 0, takeProfit = 0;
            double tpPoints = InpGridInterval;
            double slPoints = InpStopLoss;
            if(positionInfo.SelectByTicket(triggerPositionTicket) && positionInfo.StopLoss() > 0)
               slPoints = MathAbs(currentPrice - positionInfo.StopLoss()) / _Point;

            if(CalculateStopLevels(POSITION_TYPE_SELL, currentPrice, slPoints, tpPoints, stopLoss, takeProfit)) {
               if(trade.Sell(InpLotSize, _Symbol, 0, stopLoss, takeProfit, comment)) {
                  ulong ticket = trade.ResultOrder();
                  PrintFormat("✅ Grid Contra SELL_%d aberto: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                              i, ticket, trade.ResultPrice(), stopLoss, takeProfit);
                  gridLevelContraUsedSell[i]         = true;
                  gridOrdersContraSell[i].ticket     = ticket;
                  gridOrdersContraSell[i].price      = trade.ResultPrice();
                  gridOrdersContraSell[i].takeProfit = takeProfit;
                  gridOrdersContraSell[i].comment    = comment;
                  gridOrdersContraSell[i].isActive   = true;
                  if(InpShowGridLines) UpdateGridLines();
               } else {
                  PrintFormat("❌ Erro Grid Contra SELL_%d: %d - %s", i, trade.ResultRetcode(), trade.ResultRetcodeDescription());
                  if(trade.ResultRetcode() == 10016 || trade.ResultRetcode() == 10017) {
                     if(trade.Sell(InpLotSize, _Symbol, 0, 0, 0, comment)) {
                        ulong ticket = trade.ResultOrder();
                        gridLevelContraUsedSell[i]      = true;
                        gridOrdersContraSell[i].ticket  = ticket;
                        gridOrdersContraSell[i].price   = trade.ResultPrice();
                        gridOrdersContraSell[i].takeProfit = 0;
                        gridOrdersContraSell[i].comment = comment;
                        gridOrdersContraSell[i].isActive = true;
                        if(InpShowGridLines) UpdateGridLines();
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Função para atualizar ordem limite A FAVOR                        |
//+------------------------------------------------------------------+
void UpdateAFavorLimitOrder() {
   if(!triggerPositionOpen || InpGridType != GRID_DYNAMIC) return;

   double currentPrice = GetCurrentPrice();
   if(currentPrice <= 0) {
      PrintFormat("ERRO: Preço inválido em UpdateAFavorLimitOrder.");
      return;
   }

   double point    = _Point;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   double triggerStopLoss = 0;
   if(positionInfo.SelectByTicket(triggerPositionTicket))
      triggerStopLoss = positionInfo.StopLoss();

   if(triggerPositionType == POSITION_TYPE_BUY) {
      double nextPotentialLevel = gridAFavorLastPriceBuy + InpGridInterval * point;
      if(currentPrice > nextPotentialLevel) {
         double newLimitLevel = NormalizeDouble(currentPrice - InpGridInterval * point, _Digits);
         if(newLimitLevel >= currentPrice - tickSize)
            newLimitLevel = NormalizeDouble(currentPrice - tickSize, _Digits);

         if(gridAFavorOrderTicketBuy > 0) {
            if(!trade.OrderDelete(gridAFavorOrderTicketBuy))
               Print("Erro ao deletar ordem a favor (BUY) antiga: ", gridAFavorOrderTicketBuy);
            gridAFavorOrderTicketBuy = 0;
         }

         double takeProfit = NormalizeDouble(newLimitLevel + InpGridInterval * _Point, _Digits);
         string comment    = "GRID_AFAVOR_BUY_LIMIT";
         if(trade.BuyLimit(InpLotSize, newLimitLevel, _Symbol, triggerStopLoss, takeProfit, ORDER_TIME_GTC, 0, comment)) {
            gridAFavorOrderTicketBuy    = trade.ResultOrder();
            gridAFavorCurrentLevelBuy  = newLimitLevel;
            gridAFavorActiveGridBuy    = true;
            gridAFavorLastPriceBuy     = currentPrice;
            PrintFormat("Ordem Limite A Favor (BUY) colocada: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                        gridAFavorOrderTicketBuy, newLimitLevel, triggerStopLoss, takeProfit);
            if(InpShowGridLines) UpdateGridLines();
         } else {
            PrintFormat("Erro ao colocar ordem limite a favor (BUY): %.2f, Erro: %d - %s",
                        newLimitLevel, trade.ResultRetcode(), trade.ResultRetcodeDescription());
            gridAFavorActiveGridBuy = false;
         }
      }

      if(gridAFavorActiveGridBuy) {
         bool orderExists = false;
         for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(orderInfo.SelectByIndex(i))
               if(orderInfo.Ticket() == gridAFavorOrderTicketBuy && orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber) {
                  orderExists = true; break;
               }
         }
         if(!orderExists) {
            Print("Ordem limite a favor (BUY) executada! Nível: ", gridAFavorCurrentLevelBuy);
            double newReferencePrice    = gridAFavorCurrentLevelBuy;
            ulong  executedPositionTicket = 0;

            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(positionInfo.SelectByIndex(i)) {
                  if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber &&
                     positionInfo.PositionType() == POSITION_TYPE_BUY)
                  {
                     double posOpenPrice = positionInfo.PriceOpen();
                     if(MathAbs(posOpenPrice - gridAFavorCurrentLevelBuy) < tickSize * 10 &&
                        TimeCurrent() - positionInfo.Time() < 30)
                     {
                        newReferencePrice       = posOpenPrice;
                        executedPositionTicket  = positionInfo.Ticket();
                        PrintFormat("✅ Posição A Favor (BUY) identificada: Ticket=%d, Preço=%.2f, TP=%.2f",
                                    executedPositionTicket, newReferencePrice, positionInfo.TakeProfit());
                        break;
                     }
                  }
               }
            }

            if(executedPositionTicket == 0) {
               Print("⚠️ AVISO: Posição a favor não identificada. Resetando controle sem reset do grid.");
               gridAFavorOrderTicketBuy   = 0;
               gridAFavorCurrentLevelBuy  = 0;
               gridAFavorActiveGridBuy    = false;
               return;
            }

            ResetGridOrders(executedPositionTicket);
            triggerEntryPrice          = newReferencePrice;
            gridInitialized            = false;
            gridAFavorOrderTicketBuy   = 0;
            gridAFavorCurrentLevelBuy  = 0;
            gridAFavorActiveGridBuy    = false;
            gridAFavorLastPriceBuy     = newReferencePrice;
            PrintFormat("Grid resetado. Nova referência: %.2f", newReferencePrice);
         }
      }
   } else {
      double nextPotentialLevel = gridAFavorLastPriceSell - InpGridInterval * point;
      if(currentPrice < nextPotentialLevel) {
         double newLimitLevel = NormalizeDouble(currentPrice + InpGridInterval * point, _Digits);
         if(newLimitLevel <= currentPrice + tickSize)
            newLimitLevel = NormalizeDouble(currentPrice + tickSize, _Digits);

         if(gridAFavorOrderTicketSell > 0) {
            if(!trade.OrderDelete(gridAFavorOrderTicketSell))
               Print("Erro ao deletar ordem a favor (SELL) antiga: ", gridAFavorOrderTicketSell);
            gridAFavorOrderTicketSell = 0;
         }

         double takeProfit = NormalizeDouble(newLimitLevel - InpGridInterval * _Point, _Digits);
         string comment    = "GRID_AFAVOR_SELL_LIMIT";
         if(trade.SellLimit(InpLotSize, newLimitLevel, _Symbol, triggerStopLoss, takeProfit, ORDER_TIME_GTC, 0, comment)) {
            gridAFavorOrderTicketSell   = trade.ResultOrder();
            gridAFavorCurrentLevelSell  = newLimitLevel;
            gridAFavorActiveGridSell    = true;
            gridAFavorLastPriceSell     = currentPrice;
            PrintFormat("Ordem Limite A Favor (SELL) colocada: Ticket=%d, Preço=%.2f, SL=%.2f, TP=%.2f",
                        gridAFavorOrderTicketSell, newLimitLevel, triggerStopLoss, takeProfit);
            if(InpShowGridLines) UpdateGridLines();
         } else {
            PrintFormat("Erro ao colocar ordem limite a favor (SELL): %.2f, Erro: %d - %s",
                        newLimitLevel, trade.ResultRetcode(), trade.ResultRetcodeDescription());
            gridAFavorActiveGridSell = false;
         }
      }

      if(gridAFavorActiveGridSell) {
         bool orderExists = false;
         for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(orderInfo.SelectByIndex(i))
               if(orderInfo.Ticket() == gridAFavorOrderTicketSell && orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber) {
                  orderExists = true; break;
               }
         }
         if(!orderExists) {
            Print("Ordem limite a favor (SELL) executada! Nível: ", gridAFavorCurrentLevelSell);
            double newReferencePrice      = gridAFavorCurrentLevelSell;
            ulong  executedPositionTicket = 0;

            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(positionInfo.SelectByIndex(i)) {
                  if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber &&
                     positionInfo.PositionType() == POSITION_TYPE_SELL)
                  {
                     double posOpenPrice = positionInfo.PriceOpen();
                     if(MathAbs(posOpenPrice - gridAFavorCurrentLevelSell) < tickSize * 10 &&
                        TimeCurrent() - positionInfo.Time() < 30)
                     {
                        newReferencePrice      = posOpenPrice;
                        executedPositionTicket = positionInfo.Ticket();
                        PrintFormat("✅ Posição A Favor (SELL) identificada: Ticket=%d, Preço=%.2f, TP=%.2f",
                                    executedPositionTicket, newReferencePrice, positionInfo.TakeProfit());
                        break;
                     }
                  }
               }
            }

            if(executedPositionTicket == 0) {
               Print("⚠️ AVISO: Posição a favor SELL não identificada. Resetando controle.");
               gridAFavorOrderTicketSell  = 0;
               gridAFavorCurrentLevelSell = 0;
               gridAFavorActiveGridSell   = false;
               return;
            }

            ResetGridOrders(executedPositionTicket);
            triggerEntryPrice          = newReferencePrice;
            gridInitialized            = false;
            gridAFavorOrderTicketSell  = 0;
            gridAFavorCurrentLevelSell = 0;
            gridAFavorActiveGridSell   = false;
            gridAFavorLastPriceSell    = newReferencePrice;
            PrintFormat("Grid resetado. Nova referência: %.2f", newReferencePrice);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Função para resetar grid preservando posição a favor             |
//+------------------------------------------------------------------+
void ResetGridOrders(ulong preservePositionTicket = 0) {
   Print("Resetando grid (exceto gatilho original e posição preservada)...");

   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(orderInfo.SelectByIndex(i)) {
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber) {
            string comment = orderInfo.Comment();
            if(StringFind(comment, "GRID_AFAVOR_") >= 0 || StringFind(comment, "GRID_CONTRA_") >= 0)
               if(!trade.OrderDelete(orderInfo.Ticket()))
                  Print("Erro ao deletar ordem do grid: ", orderInfo.Ticket());
         }
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber) {
            ulong currentTicket = positionInfo.Ticket();
            if(currentTicket == triggerPositionTicket) continue;
            if(preservePositionTicket > 0 && currentTicket == preservePositionTicket) {
               PrintFormat("Preservando posição a favor: Ticket=%d, Preço=%.2f, TP=%.2f",
                           currentTicket, positionInfo.PriceOpen(), positionInfo.TakeProfit());
               continue;
            }
            string comment = positionInfo.Comment();
            if(StringFind(comment, "GRID_AFAVOR_") >= 0 || StringFind(comment, "GRID_CONTRA_") >= 0)
               if(!trade.PositionClose(currentTicket))
                  Print("Erro ao fechar posição do grid: ", currentTicket);
         }
      }
   }

   ArrayFill(gridLevelContraUsedBuy,  0, InpGridLevels, false);
   ArrayFill(gridLevelContraUsedSell, 0, InpGridLevels, false);
   ArrayFree(gridOrdersContraBuy);
   ArrayFree(gridOrdersContraSell);
   ArrayResize(gridOrdersContraBuy,  InpGridLevels);
   ArrayResize(gridOrdersContraSell, InpGridLevels);

   gridAFavorOrderTicketBuy   = 0;
   gridAFavorOrderTicketSell  = 0;
   gridAFavorCurrentLevelBuy  = 0;
   gridAFavorCurrentLevelSell = 0;
   gridAFavorActiveGridBuy    = false;
   gridAFavorActiveGridSell   = false;

   DeleteGridLines(false);
   Print("Reset do grid concluído. Posição preservada: ", preservePositionTicket);
}

//+------------------------------------------------------------------+
//| Função para desenhar as linhas do grid                            |
//+------------------------------------------------------------------+
void DrawGridLines() {
   if(!triggerPositionOpen) return;
   DeleteGridLines(true);

   color gridLineColor  = clrDarkGray;
   color usedLineColor  = clrRed;
   color favorLineColor = clrGreen;
   color refLineColor   = (triggerPositionType == POSITION_TYPE_BUY) ? clrBlue : clrRed;

   string refLineName = "GridReferenciaAtual";
   ObjectCreate(0, refLineName, OBJ_HLINE, 0, 0, triggerEntryPrice);
   ObjectSetInteger(0, refLineName, OBJPROP_COLOR, refLineColor);
   ObjectSetInteger(0, refLineName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, refLineName, OBJPROP_WIDTH, 2);
   ObjectSetString(0, refLineName, OBJPROP_TEXT, "Ref Grid: " + DoubleToString(triggerEntryPrice, _Digits));
   ObjectSetInteger(0, refLineName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, refLineName, OBJPROP_BACK, true);

   if(triggerPositionType == POSITION_TYPE_BUY) {
      for(int i = 0; i < InpGridLevels; i++) {
         string lineName = "GridContraBuy" + IntegerToString(i);
         ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, gridLevelsContraBuy[i]);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, gridLevelContraUsedBuy[i] ? usedLineColor : gridLineColor);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
         ObjectSetString(0, lineName, OBJPROP_TEXT, "Contra Buy " + IntegerToString(i+1));
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      }
      if(InpGridType == GRID_DYNAMIC && gridAFavorOrderTicketBuy > 0) {
         string favorLineName = "GridAFavorBuyLimit";
         ObjectCreate(0, favorLineName, OBJ_HLINE, 0, 0, gridAFavorCurrentLevelBuy);
         ObjectSetInteger(0, favorLineName, OBJPROP_COLOR, favorLineColor);
         ObjectSetInteger(0, favorLineName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, favorLineName, OBJPROP_WIDTH, 1);
         ObjectSetString(0, favorLineName, OBJPROP_TEXT, "A Favor Buy: " + DoubleToString(gridAFavorCurrentLevelBuy, _Digits));
         ObjectSetInteger(0, favorLineName, OBJPROP_SELECTABLE, false);
      }
   } else {
      for(int i = 0; i < InpGridLevels; i++) {
         string lineName = "GridContraSell" + IntegerToString(i);
         ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, gridLevelsContraSell[i]);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, gridLevelContraUsedSell[i] ? usedLineColor : gridLineColor);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
         ObjectSetString(0, lineName, OBJPROP_TEXT, "Contra Sell " + IntegerToString(i+1));
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      }
      if(InpGridType == GRID_DYNAMIC && gridAFavorOrderTicketSell > 0) {
         string favorLineName = "GridAFavorSellLimit";
         ObjectCreate(0, favorLineName, OBJ_HLINE, 0, 0, gridAFavorCurrentLevelSell);
         ObjectSetInteger(0, favorLineName, OBJPROP_COLOR, favorLineColor);
         ObjectSetInteger(0, favorLineName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, favorLineName, OBJPROP_WIDTH, 1);
         ObjectSetString(0, favorLineName, OBJPROP_TEXT, "A Favor Sell: " + DoubleToString(gridAFavorCurrentLevelSell, _Digits));
         ObjectSetInteger(0, favorLineName, OBJPROP_SELECTABLE, false);
      }
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função para atualizar as linhas do grid                           |
//+------------------------------------------------------------------+
void UpdateGridLines() {
   if(!InpShowGridLines || !triggerPositionOpen) return;

   color gridLineColor  = clrDarkGray;
   color usedLineColor  = clrRed;
   color favorLineColor = clrGreen;

   if(triggerPositionType == POSITION_TYPE_BUY) {
      for(int i = 0; i < InpGridLevels; i++) {
         string lineName = "GridContraBuy" + IntegerToString(i);
         if(ObjectFind(0, lineName) >= 0)
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, gridLevelContraUsedBuy[i] ? usedLineColor : gridLineColor);
      }
      if(InpGridType == GRID_DYNAMIC) {
         ObjectDelete(0, "GridAFavorBuyLimit");
         if(gridAFavorOrderTicketBuy > 0) {
            ObjectCreate(0, "GridAFavorBuyLimit", OBJ_HLINE, 0, 0, gridAFavorCurrentLevelBuy);
            ObjectSetInteger(0, "GridAFavorBuyLimit", OBJPROP_COLOR, favorLineColor);
            ObjectSetInteger(0, "GridAFavorBuyLimit", OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, "GridAFavorBuyLimit", OBJPROP_WIDTH, 1);
            ObjectSetString(0, "GridAFavorBuyLimit", OBJPROP_TEXT, "A Favor Buy: " + DoubleToString(gridAFavorCurrentLevelBuy, _Digits));
            ObjectSetInteger(0, "GridAFavorBuyLimit", OBJPROP_SELECTABLE, false);
         }
      }
   } else {
      for(int i = 0; i < InpGridLevels; i++) {
         string lineName = "GridContraSell" + IntegerToString(i);
         if(ObjectFind(0, lineName) >= 0)
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, gridLevelContraUsedSell[i] ? usedLineColor : gridLineColor);
      }
      if(InpGridType == GRID_DYNAMIC) {
         ObjectDelete(0, "GridAFavorSellLimit");
         if(gridAFavorOrderTicketSell > 0) {
            ObjectCreate(0, "GridAFavorSellLimit", OBJ_HLINE, 0, 0, gridAFavorCurrentLevelSell);
            ObjectSetInteger(0, "GridAFavorSellLimit", OBJPROP_COLOR, favorLineColor);
            ObjectSetInteger(0, "GridAFavorSellLimit", OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, "GridAFavorSellLimit", OBJPROP_WIDTH, 1);
            ObjectSetString(0, "GridAFavorSellLimit", OBJPROP_TEXT, "A Favor Sell: " + DoubleToString(gridAFavorCurrentLevelSell, _Digits));
            ObjectSetInteger(0, "GridAFavorSellLimit", OBJPROP_SELECTABLE, false);
         }
      }
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função para remover as linhas do grid                             |
//+------------------------------------------------------------------+
void DeleteGridLines(bool deleteReference = true) {
   ObjectsDeleteAll(0, "GridContraBuy");
   ObjectsDeleteAll(0, "GridContraSell");
   ObjectDelete(0, "GridAFavorBuyLimit");
   ObjectDelete(0, "GridAFavorSellLimit");
   if(deleteReference) ObjectDelete(0, "GridReferenciaAtual");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função para verificar gatilhos                                    |
//+------------------------------------------------------------------+
void CheckTriggers() {
   CheckStatsTrigger();
}

//+------------------------------------------------------------------+
//| FUNÇÃO CORRIGIDA: Verificar gatilho por percentual               |
//| CORREÇÃO PRINCIPAL: Comparação int vs string substituída por     |
//| comparação int vs int (g_currentTime >= g_startTimeHHMM)        |
//+------------------------------------------------------------------+
void CheckStatsTrigger() {

   // *** VALIDAÇÃO: Garantir que os preços estão calculados ***
   if(g_precoEntradaV <= 0 || g_precoEntradaC <= 0 || g_aberturaDia <= 0) {
      PrintFormat("TRIGGER: Preços não disponíveis ainda. abertura=%.2f, entradaC=%.2f, entradaV=%.2f",
                  g_aberturaDia, g_precoEntradaC, g_precoEntradaV);
      return;
   }

   // *** VALIDAÇÃO: Verificar se o candle de referência tem dados ***
   if(g_fechamentoBarra <= 0) {
      Print("TRIGGER: Fechamento da barra ainda não disponível.");
      return;
   }

   // *** CORREÇÃO PRINCIPAL: Comparar int com int ***
   // g_currentTime é int HHMM (ex: 930)
   // g_startTimeHHMM é int HHMM calculado de InpStartTime (ex: 900)
   // ANTES (ERRADO): g_currentTime > InpStartTime  (int vs string -> sempre false!)
   // DEPOIS (CERTO):  g_currentTime >= g_startTimeHHMM

   PrintFormat("TRIGGER CHECK: hora=%d >= inicio=%d | fechaBarra=%.2f | entradaV=%.2f | entradaC=%.2f",
               g_currentTime, g_startTimeHHMM, g_fechamentoBarra, g_precoEntradaV, g_precoEntradaC);

   // Gatilho de VENDA: fechamento da barra abaixo do preço de entrada de venda
   if(g_currentTime >= g_startTimeHHMM && g_fechamentoBarra < g_precoEntradaV) {
      PrintFormat("🔴 TRIGGER VENDA acionado! Barra (%.2f) < EntradaV (%.2f)",
                  g_fechamentoBarra, g_precoEntradaV);
      OpenTriggerPosition(tendencia ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
      return; // Evitar duplo trigger no mesmo tick
   }

   // Gatilho de COMPRA: fechamento da barra acima do preço de entrada de compra
   if(g_currentTime >= g_startTimeHHMM && g_fechamentoBarra > g_precoEntradaC) {
      PrintFormat("🟢 TRIGGER COMPRA acionado! Barra (%.2f) > EntradaC (%.2f)",
                  g_fechamentoBarra, g_precoEntradaC);
      OpenTriggerPosition(tendencia ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
   }
}


//+------------------------------------------------------------------+
//| Função para criar o painel visual                                 |
//+------------------------------------------------------------------+
void CreatePanel() {
   DeletePanel();
   int x = 20, y = 20, width = 220;
   int height = panelMinimized ? 30 : 240;

   ObjectCreate(0, panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelName, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, panelName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, panelName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, panelName, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, panelName, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, panelName, OBJPROP_BGCOLOR, InpPanelColor);
   ObjectSetInteger(0, panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, panelName, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, panelName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, panelName, OBJPROP_BACK, false);
   ObjectSetInteger(0, panelName, OBJPROP_SELECTABLE, false);

   ObjectCreate(0, panelMinimizeButton, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_XDISTANCE, x + width - 25);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_YDISTANCE, y + 5);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_XSIZE, 20);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_BGCOLOR, InpPanelColor);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, panelMinimizeButton, OBJPROP_TEXT, panelMinimized ? "+" : "-");
   ObjectSetString(0, panelMinimizeButton, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_FONTSIZE, 12);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, panelMinimizeButton, OBJPROP_STATE, false);

   if(panelMinimized) {
      CreatePanelLabel(0, x + 10, y + 8, "Gradiente MANUS V1.5 - Status...", InpTextColor, 8, width - 40);
   } else {
      int buttonY = y + height - 35, buttonWidth = 60, buttonSpacing = 5;

      ObjectCreate(0, panelBuyButton, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_XDISTANCE, x + 10);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_YDISTANCE, buttonY);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_XSIZE, buttonWidth);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_YSIZE, 30);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_BGCOLOR, clrGreen);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_BORDER_COLOR, clrWhite);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, panelBuyButton, OBJPROP_TEXT, "COMPRAR");
      ObjectSetString(0, panelBuyButton, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, panelBuyButton, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, panelBuyButton, OBJPROP_STATE, false);

      ObjectCreate(0, panelSellButton, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, panelSellButton, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, panelSellButton, OBJPROP_XDISTANCE, x + 10 + buttonWidth + buttonSpacing);
      ObjectSetInteger(0, panelSellButton, OBJPROP_YDISTANCE, buttonY);
      ObjectSetInteger(0, panelSellButton, OBJPROP_XSIZE, buttonWidth);
      ObjectSetInteger(0, panelSellButton, OBJPROP_YSIZE, 30);
      ObjectSetInteger(0, panelSellButton, OBJPROP_BGCOLOR, clrRed);
      ObjectSetInteger(0, panelSellButton, OBJPROP_BORDER_COLOR, clrWhite);
      ObjectSetInteger(0, panelSellButton, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, panelSellButton, OBJPROP_TEXT, "VENDER");
      ObjectSetString(0, panelSellButton, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, panelSellButton, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, panelSellButton, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, panelSellButton, OBJPROP_STATE, false);

      ObjectCreate(0, panelCloseButton, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, panelCloseButton, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, panelCloseButton, OBJPROP_XDISTANCE, x + 10 + 2 * (buttonWidth + buttonSpacing));
      ObjectSetInteger(0, panelCloseButton, OBJPROP_YDISTANCE, buttonY);
      ObjectSetInteger(0, panelCloseButton, OBJPROP_XSIZE, buttonWidth);
      ObjectSetInteger(0, panelCloseButton, OBJPROP_YSIZE, 30);
      ObjectSetInteger(0, panelCloseButton, OBJPROP_BGCOLOR, clrDarkGray);
      ObjectSetInteger(0, panelCloseButton, OBJPROP_BORDER_COLOR, clrWhite);
      ObjectSetInteger(0, panelCloseButton, OBJPROP_COLOR, clrWhite);
      ObjectSetString(0, panelCloseButton, OBJPROP_TEXT, "ZERAR");
      ObjectSetString(0, panelCloseButton, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, panelCloseButton, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, panelCloseButton, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, panelCloseButton, OBJPROP_STATE, false);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função para atualizar o painel visual                             |
//+------------------------------------------------------------------+
void UpdatePanel(ENUM_TIME_STATUS timeStatus) {
   if(panelMinimized) {
      string quickStatus = "Gradiente MANUS V1.5";
      if(InpSwingTradeMode) quickStatus += " [SWING]";
      quickStatus += triggerPositionOpen ? " - OPERANDO" : " - AGUARDANDO";
      CreatePanelLabel(0, 30, 28, quickStatus, InpTextColor, 8, 160);
      ChartRedraw();
      return;
   }

   panelInfo.symbol       = _Symbol;
   panelInfo.currentPrice = symbolInfo.Last();
   panelInfo.dailyProfit  = dailyProfit;
   panelInfo.weeklyProfit = weeklyProfit;
   panelInfo.monthlyProfit = monthlyProfit;
   panelInfo.totalTrades  = totalTrades;

   int activeTrades = 0;
   double currentFloatingProfit = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber) {
            activeTrades++;
            currentFloatingProfit += positionInfo.Profit() + positionInfo.Swap() + positionInfo.Commission();
         }
   }
   panelInfo.activeTrades = activeTrades;

   if(triggerPositionOpen) {
      panelInfo.gridStatus = (InpGridType == GRID_FIXED) ? "Grid Fixo Ativo" : "Grid Dinâmico Ativo";
      if(gridAFavorOrderTicketBuy > 0)  panelInfo.gridStatus += " (Ord C Fav)";
      if(gridAFavorOrderTicketSell > 0) panelInfo.gridStatus += " (Ord V Fav)";
   } else {
      panelInfo.gridStatus = "Grid Inativo";
   }

   if(dailyLimitReached)
      panelInfo.triggerStatus = "LIMITE DIÁRIO ATINGIDO";
   else if(!InpSwingTradeMode && timeStatus == TIME_CLOSE)
      panelInfo.triggerStatus = "HORÁRIO DE FECHAMENTO";
   else if(!InpSwingTradeMode && timeStatus == TIME_INACTIVE)
      panelInfo.triggerStatus = "FORA DO HORÁRIO";
   else if(triggerPositionOpen) {
      panelInfo.triggerStatus = (triggerPositionType == POSITION_TYPE_BUY) ? "OPERANDO COMPRADO" : "OPERANDO VENDIDO";
      if(InpSwingTradeMode) panelInfo.triggerStatus += " [SWING]";
   } else {
      panelInfo.triggerStatus = "Aguardando Gatilho (Porcentagem)";
      if(InpSwingTradeMode) panelInfo.triggerStatus += " [SWING]";
   }

   int labelX = 30, labelY = 30, labelSpacing = 15, panelWidth = 220;

   CreatePanelLabel(0, labelX, labelY, "Gradiente MANUS V1.5 CORRIGIDO", InpTextColor, 10, panelWidth - labelX * 2);
   labelY += labelSpacing + 5;

   color statusColor = clrWhite;
   if(dailyLimitReached || (!InpSwingTradeMode && timeStatus == TIME_CLOSE)) statusColor = clrRed;
   else if(!InpSwingTradeMode && timeStatus == TIME_INACTIVE) statusColor = clrGray;
   else if(triggerPositionOpen) statusColor = clrOrange;
   CreatePanelLabel(1, labelX, labelY, panelInfo.triggerStatus, statusColor, 8, panelWidth - labelX * 2);
   labelY += labelSpacing;

   CreatePanelLabel(2, labelX, labelY, "Resultado Dia: R$ " + DoubleToString(panelInfo.dailyProfit, 2),
                    panelInfo.dailyProfit >= 0 ? clrLimeGreen : clrRed, 8, panelWidth - labelX * 2);
   labelY += labelSpacing;

   CreatePanelLabel(3, labelX, labelY, "Flutuante: R$ " + DoubleToString(currentFloatingProfit, 2),
                    currentFloatingProfit >= 0 ? clrLimeGreen : clrRed, 8, panelWidth - labelX * 2);
   labelY += labelSpacing;

   CreatePanelLabel(4, labelX, labelY, "Posições Abertas: " + IntegerToString(panelInfo.activeTrades), InpTextColor, 8, panelWidth - labelX * 2);
   labelY += labelSpacing;

   CreatePanelLabel(5, labelX, labelY, "Grid: " + panelInfo.gridStatus, InpTextColor, 8, panelWidth - labelX * 2);
   labelY += labelSpacing;

   if(triggerPositionOpen) {
      CreatePanelLabel(6, labelX, labelY, "Ref. Grid: " + DoubleToString(triggerEntryPrice, _Digits), InpTextColor, 8, panelWidth - labelX * 2);
      labelY += labelSpacing;
   }

   // Mostrar preços de entrada no painel
   CreatePanelLabel(7, labelX, labelY,
                    "Entrada C: " + DoubleToString(g_precoEntradaC, 0) +
                    " | V: " + DoubleToString(g_precoEntradaV, 0),
                    clrYellow, 8, panelWidth - labelX * 2);
   labelY += labelSpacing;

   CreatePanelLabel(8, labelX, labelY, "M#: " + IntegerToString(InpMagicNumber), clrDimGray, 8, panelWidth - labelX * 2);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função para criar um label no painel                              |
//+------------------------------------------------------------------+
void CreatePanelLabel(int index, int x, int y, string text, color textColor, int fontSize, int width = 0) {
   string labelName = "PanelLabel_" + IntegerToString(index);
   ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, labelName, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, textColor);
   ObjectSetString(0, labelName, OBJPROP_TEXT, text);
   ObjectSetString(0, labelName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   if(width > 0) ObjectSetInteger(0, labelName, OBJPROP_XSIZE, width);
}

//+------------------------------------------------------------------+
//| Função para remover o painel visual                               |
//+------------------------------------------------------------------+
void DeletePanel() {
   ObjectDelete(0, panelName);
   ObjectDelete(0, panelMinimizeButton);
   ObjectDelete(0, panelBuyButton);
   ObjectDelete(0, panelSellButton);
   ObjectDelete(0, panelCloseButton);
   ObjectsDeleteAll(0, "PanelLabel_");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Função para processar cliques em objetos                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(sparam == panelMinimizeButton) {
         panelMinimized = !panelMinimized;
         CreatePanel();
         return;
      }
      if(panelMinimized) return;

      if(sparam == panelBuyButton) {
         ENUM_TIME_STATUS timeStatus = CheckTimeStatus();
         if(!triggerPositionOpen && (InpSwingTradeMode || timeStatus == TIME_ACTIVE) && !dailyLimitReached) {
            Print("Botão COMPRAR clicado.");
            OpenTriggerPosition(POSITION_TYPE_BUY);
         } else
            Print("Botão COMPRAR ignorado (operação já aberta, fora de horário ou limite atingido).");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw();
         return;
      }
      if(sparam == panelSellButton) {
         ENUM_TIME_STATUS timeStatus = CheckTimeStatus();
         if(!triggerPositionOpen && (InpSwingTradeMode || timeStatus == TIME_ACTIVE) && !dailyLimitReached) {
            Print("Botão VENDER clicado.");
            OpenTriggerPosition(POSITION_TYPE_SELL);
         } else
            Print("Botão VENDER ignorado.");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw();
         return;
      }
      if(sparam == panelCloseButton) {
         Print("Botão ZERAR clicado.");
         CloseAllPositions();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw();
         return;
      }
   }
}


//+------------------------------------------------------------------+
//| Atualizar dados de mercado                                        |
//+------------------------------------------------------------------+
void AtualizarDadosDoMercado() {
   g_fechaAnterior  = iClose(_Symbol, PERIOD_D1, 1);
   g_aberturaDia    = iOpen(_Symbol, PERIOD_D1, 0);
   g_precoAtual     = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   MqlRates BarData[1];
   if(CopyRates(_Symbol, mm_tempo_grafico, 0, 1, BarData) > 0)
      g_fechamentoBarra = BarData[0].close;
   else
      g_fechamentoBarra = g_precoAtual; // Fallback para preço atual
}

//+------------------------------------------------------------------+
//| Calcular preços de entrada baseados no percentual                 |
//+------------------------------------------------------------------+
void CalcularPrecosDeEntrada() {
   if(g_aberturaDia <= 0) {
      Print("AVISO: Abertura do dia inválida. Aguardando dados...");
      return;
   }
   g_precoEntradaC = g_aberturaDia * (1.0 + perc_alta  / 100.0);
   g_precoEntradaV = g_aberturaDia * (1.0 - perc_queda / 100.0);
   PrintFormat("Preços calculados: Abertura=%.2f | EntradaC=%.2f (+%.1f%%) | EntradaV=%.2f (-%.1f%%)",
               g_aberturaDia, g_precoEntradaC, perc_alta, g_precoEntradaV, perc_queda);
}

//+------------------------------------------------------------------+
//| Gerenciar horários                                                |
//+------------------------------------------------------------------+
void GerenciarHorarios() {
   datetime timeNow = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(timeNow, tm);
   g_currentTime = tm.hour * 100 + tm.min; // Ex: 09:30 -> 930
}

//+------------------------------------------------------------------+
//| Verificar se é um novo candle                                     |
//+------------------------------------------------------------------+
bool NovoCandle() {
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, mm_tempo_grafico, 0);
   if(last_bar_time != current_bar_time) {
      last_bar_time = current_bar_time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Desenhar linhas de entrada no gráfico                             |
//+------------------------------------------------------------------+
void DesenharLinhas() {
   ObjectDelete(0, "LinhaPercentualAlta");
   ObjectDelete(0, "LinhaPercentualQueda");

   ObjectCreate(0, "LinhaPercentualQueda", OBJ_HLINE, 0, 0, g_precoEntradaV);
   ObjectSetInteger(0, "LinhaPercentualQueda", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "LinhaPercentualQueda", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LinhaPercentualQueda", OBJPROP_WIDTH, 1);
   ObjectSetString(0, "LinhaPercentualQueda", OBJPROP_TEXT, "Venda: " + DoubleToString(g_precoEntradaV, _Digits));

   ObjectCreate(0, "LinhaPercentualAlta", OBJ_HLINE, 0, 0, g_precoEntradaC);
   ObjectSetInteger(0, "LinhaPercentualAlta", OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, "LinhaPercentualAlta", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LinhaPercentualAlta", OBJPROP_WIDTH, 1);
   ObjectSetString(0, "LinhaPercentualAlta", OBJPROP_TEXT, "Compra: " + DoubleToString(g_precoEntradaC, _Digits));

   ChartRedraw();
}
