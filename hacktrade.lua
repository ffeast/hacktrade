--[[

 HackTrade
 Nano-framework for HFT-robots development.
 Docs: https://github.com/ffeast/hacktrade
 -----------------------------------------------------------
 © Denis Kolodin and https://github.com/ffeast

--]]

-- SERVICE FUNCTIONS
function table.reverse(tab)
  local size = #tab
  local ntab = {}
  for i, v in ipairs(tab) do
    ntab[size - i + 1] = v
  end
  return ntab
end

function table.transform(tab, felem)
  local ntab = {}
  for idx = 1, #tab do
    ntab[idx] = felem(tab[idx])
  end
  return ntab
end

function bitand(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
      if a % 2 == 1 and b % 2 == 1 then -- test the rightmost bits
          result = result + bitval      -- set the current bit
      end
      bitval = bitval * 2 -- shift left
      a = math.floor(a / 2) -- shift right
      b = math.floor(b / 2)
    end
    return result
end

-- CONSTANTS
QUIK = {
  TYPE = {
    DOUBLE = 1,
    LONG = 2,
    CHAR = 3,
    ENUM = 4,
    TIME = 5,
    DATE = 6
  },
  TRANS_REPLY = {
    SENT = 0,
    RECEIVED = 1,
    NOGATE = 2,
    COMPLETE = 3,
    INCOMPLETE = 4,
    REJECTED = 5,
    BAD_LIMITS = 6,
    UNSUPPORTED = 10,
    SIGNATURE_FAILED = 11,
    NORESPONSE = 12,
    CROSS = 13
  },
  ORDER_BITMAP = {
    ACTIVE = 0x1,
    REJECTED = 0x2,
    BUY = 0x4,
    LIMITED = 0x8,
    DIFF_PRICE = 0x10,
    FILL_OR_KILL = 0x20,
    MARKET_MAKER = 0x40,
    ACCEPTED = 0x80,
    REMAINDER = 0x100,
    ICEBERG = 0x200
  },
  MARKET = {
    STOCKS = "TQBR",
    FUTS = "SPBFUT",
    ETFS = "TQTF"
  },
  LIMIT_KIND = {
    T0 = 0,
    T2 = 2
  }
}

Trade = coroutine.yield

-- OOP support
__object_behaviour = {
  __call = function(meta, o)
    if meta.__index == nil then
      setmetatable(o, {__index = meta})
    else
      setmetatable(o, meta)
    end
    if meta.init ~= nil then
      meta.init(o)
    end
    return o
  end
}

function round(num, idp)
  local mult = 10 ^ (idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

-- SERVER INFO
ServerInfo = {retry_on_empty = false, retry_delay_msec = 1000}
function ServerInfo:__index(key)
  if ServerInfo[key] ~= nil then
    return ServerInfo[key]
  end
  local res
  while true do
    res = getInfoParam(string.upper(key))
    if res == '' then
      res = nil
    end
    if res ~= nil then
      return res
    else
      if self.retry_on_empty == true then
        sleep(self.retry_delay_msec)
      else
        break
      end
    end
  end
  return res
end
setmetatable(ServerInfo, __object_behaviour)

-- MARKET DATA
MarketData = {}
function MarketData._pvconverter(elem)
  local nelem = {}
  nelem.price = tonumber(elem.price)
  nelem.quantity = tonumber(elem.quantity)
  return nelem
end
function MarketData:init()
  log:trace("marketData created: " .. self.market .. " " .. self.ticker)
end
function MarketData:__index(key)
  if MarketData[key] ~= nil then
    return MarketData[key]
  end
  if key == "bids" then
    local data = getQuoteLevel2(self.market, self.ticker).bid or {}
    data = table.reverse(data) -- Reverse for normal order (not alphabet)!
    data = table.transform(data, self._pvconverter)
    return data or {}
  elseif key == "offers" then
    local data = getQuoteLevel2(self.market, self.ticker).offer or {}
    data = table.transform(data, self._pvconverter)
    return data or {}
  end
  local param = getParamEx(self.market, self.ticker, key)
  if next(param) == nil then
    return nil
  end
  if (tonumber(param.param_type) == QUIK.TYPE.DOUBLE
        or tonumber(param.param_type) == QUIK.TYPE.LONG) then
    return tonumber(param.param_value)
  else
    return param.param_value
  end
end
function MarketData:fit(price)
  local step = feed.sec_price_step
  local result = math.floor(price / step) * step
  return round(result, self.sec_scale)
end
function MarketData:move(price, val)
  local step = feed.sec_price_step
  local result = (math.floor(price / step) * step) + (val * step)
  return round(result, self.sec_scale)
end
setmetatable(MarketData, __object_behaviour)

-- HISTORY DATA SOURCE
History = {}
function History:__index(key)
  if math.abs(key) > #self then
    return nil
  end
  if History[key] ~= nil then
    return History[key]
  end
  if key < 0 then
    key = #self + key + 1
  end
  return self[key]
end
setmetatable(History, __object_behaviour)

-- You can access by closes_0, values, values_1
Indicator = {max_tries = 10000}
function Indicator:init()
  log:trace("indicator created with tag: " .. self.tag
            .. ", max tries: " .. tostring(self.max_tries))
end
function Indicator:__index(key)
  if Indicator[key] ~= nil then
    return Indicator[key]
  end
  local extractor = nil
  if type(key) == "number" then
    extractor = key
    key = "closes_0"
  end
  local line = key:match("%d+")
  local field = key:match("%a+")
  if line == nil then
    line = 0
  end

  local candles = 0
  local tried = 0
  while tried < self.max_tries and candles == 0 do
    if tried > 0 then
      log:trace("retry #" .. tostring(tried) .. " to load: " .. self.tag)
      sleep(100)
    end
    candles = getNumCandles(self.tag)
    tried = tried + 1
  end
  if candles == 0 then
    log:fatal("can't find data for chart with tag: "
              .. self.tag .. " after " .. self.max_tries .. " tries")
  elseif tried > 1 then
    log:trace("data load ok for: " .. self.tag)
  end

  local data, n, b = getCandlesByIndex(self.tag, tonumber(line), 0, candles)
  if n == 0 then
    log:fatal("can't load data for chart with tag: ".. self.tag)
  end
  if field ~= nil and field ~= "values" then
    field = field:sub(0, -2)
    new_data = {}
    for idx = 1, #data do
      new_data[idx] = data[idx][field]
    end
    data = new_data
  end
  local result = History(data)
  if extractor ~= nil then
    return result[extractor]
  else
    return result
  end
end
setmetatable(Indicator, __object_behaviour)

-- EXECUTION SYSTEM
SmartOrder = {
  -- 666 - Warning! This number uses for cancelling!
  lower = 1000,
  upper = 10000,
  max_tries = 10000,
  pool = {}
}
function SmartOrder:__index(key)
  if SmartOrder[key] ~= nil then
    return SmartOrder[key]
  end
  -- Dynamic fields have to be calculated!
  if key == "remainder" then
    return (self.planned - self.position)
  end
  if key == "filled" then
    return (self.planned - self.position) == 0
  end
  return nil
end
function SmartOrder:init()
  math.randomseed(os.time())
  for i = self.lower, self.upper do
    local key = math.random(self.lower, self.upper)
    -- Store unique number of transaction which can be used as pool for processing
    if SmartOrder.pool[key] == nil then
      SmartOrder.pool[key] = self
      self.trans_id = key
      break
    end
  end
  self.position = 0
  self.planned = 0
  self.order = nil
  log:trace("SmartOrder created with trans_id: " .. self.trans_id)
end
function SmartOrder:destroy()
  SmartOrder.pool[self.trans_id] = nil
end
function SmartOrder:update(price, planned)
  if price ~= nil then
    self.price = price
  end
  if planned ~= nil then
    self.planned = planned
  end
end
function SmartOrder:fill()
  local tried = 0
  while (not self.filled and tried < self.max_tries) do
    tried = tried + 1
    log:trace("waiting for order filled, tried " .. tried .. " times")
    Trade()
    sleep(10)
  end
  if not self.filled then
    self:update(nil, 0)
    Trade()
    log:fatal("Unable to complete order after "
              .. tostring(self.max_tries)
              .. " tries")
  end
end
function SmartOrder:_convert2Lots(value)
  local info = getSecurityInfo(self.market, self.ticker)
  if info == nil then
    log:fatal("unable to get security info for "
              .. tostring(self.market)
              .. " / "
              .. tostring(self.ticker))
  end
  return value / info.lot_size
end
function SmartOrder:_load_futures()
  local futs_tbl = "futures_client_holding"
  local futs_cnt = getNumberOf(futs_tbl)
  for i = 0, futs_cnt - 1 do
    local fut = getItem(futs_tbl, i)
    if fut.seccode == self.ticker then
      return fut.totalnet
    end
  end
  return 0
end
function SmartOrder:_load_stocks_or_etfs()
  local stocks_tbl = "depo_limits"
  local stocks_cnt = getNumberOf(stocks_tbl)
  for i = 0, stocks_cnt - 1 do
    local stock = getItem(stocks_tbl, i)
    if (stock.sec_code == self.ticker
          and stock.limit_kind == QUIK.LIMIT_KIND.T2) then
        return self:_convert2Lots(stock.currentbal)
    end
  end
  return 0
end
function SmartOrder:load()
  local position
  if self.market == QUIK.MARKET.FUTS then
    position = self:_load_futures()
  elseif (self.market == QUIK.MARKET.STOCKS
            or self.market == QUIK.MARKET.ETFS) then
    position = self:_load_stocks_or_etfs()
  else
    log:fatal("unsupported market: " .. tostring(self.market))
  end

  self.position = position
  self.planned = position
end
function SmartOrder:process()
  log:debug("processing SmartOrder " .. self.trans_id)
  local order = self.order
  if order ~= nil then
    local cancel = false
    if order.price ~= self.price then
      log:debug("price changed, cancelling order")
      cancel = true
    end
    local filled = order.filled * order.sign
    if self.planned - self.position - order.quantity ~= 0 then
      cancel = true
    end
    if order.active == false then
      -- Calculate only after .active flag is set!!!
      filled = order.filled * order.sign
      self.position = self.position + filled
      self.order = nil
    else
      if cancel then
        if self.order.number ~= nil then
          if self.order.cancelled ~= nil then
            if (os.time() - self.order.cancelled) > 5 then
              self.order.cancelled = nil
            end
          else
            local result = sendTransaction({
              ACCOUNT = self.account,
              CLIENT_CODE = self.client,
              CLASSCODE = self.market,
              SECCODE = self.ticker,
              TRANS_ID = "666",
              ACTION = "KILL_ORDER",
              ORDER_KEY = tostring(self.order.number)
            })
            if result == "" then
              self.order.cancelled = os.time()
            else
              log:trace("transaction sending error: " .. tostring(result))
            end
            log:debug("kill order")
          end
        end
      end
    end
  else
    local diff = self.planned - self.position
    if diff ~= 0 then
      if self.order == nil then
        local absdiff = math.abs(diff)
        log:debug("sending transaction for " .. tostring(diff) .. " items")
        self.order = {
          sign = diff / absdiff,
          price = self.price,
          quantity = diff,
          active = true,
          filled = 0,
        }
        local result = sendTransaction({
          ACCOUNT = self.account,
          CLIENT_CODE = self.client,
          CLASSCODE = self.market,
          SECCODE = self.ticker,
          TYPE = (self.price == 0 and "M") or "L",
          TRANS_ID = tostring(self.trans_id),
          ACTION = "NEW_ORDER",
          OPERATION = (diff > 0 and "B") or "S",
          PRICE = tostring(self.price),
          QUANTITY = tostring(absdiff)
        })
        if result ~= "" then
          log:warning("transaction sending error: " .. tostring(result))
        else
          log:trace("transaction ok")
        end
      end
    end
  end
end
setmetatable(SmartOrder, __object_behaviour)

-- LOGGING
log = {
    logfile = nil,
    loglevel = 0,
    loglevels = {
        [-1] = "Debug",
        [ 0] = "Trace",
        [ 1] = "Info",
        [ 2] = "Warning",
        [ 3] = "Error",
    }
}
function log:open(path)
    self.logfile = io.open(path .. ".log", "a")
end
function log:close()
    if self.logfile ~= nil then
        io.close(self.logfile)
    end
end
function log:log(log_text, log_level)
  if (log_level >= self.loglevel) then
    local msg = string.format("[%s] %s: %s\n", os.date(), self.loglevels[log_level], log_text)
    if (log_level > 0) then
      message(msg, log_level)
    end
    self.logfile:write(msg)
    self.logfile:flush()
  end
end
function log:debug(t)
  self:log(t, -1)
end
function log:trace(t)
  self:log(t, 0)
end
function log:info(t)
  self:log(t, 1)
end
function log:warning(t)
  self:log(t, 2)
end
function log:error(t)
  self:log(t, 3)
end
function log:fatal(t)
  self:error(t)
  error(t)
end
function log:setlevel(loglevel)
  self.loglevel = loglevel;
end

-- MAIN LOOP
WORKING_FLAG = true

function main()
  log:trace("robot started")
  if Start ~= nil then
    Start()
  end
  if Robot ~= nil then
    local routine = coroutine.create(Robot)
    while WORKING_FLAG do
      local res, errmsg = coroutine.resume(routine)
      if res == false then
        log:fatal("broken coroutine: " .. errmsg)
      end
      if coroutine.status(routine) == "dead" then
        log:trace("robot routine finished")
        break
      end
      -- orders processing calls after every coroutine iteration
      for trans_id, smartorder in pairs(SmartOrder.pool) do
        smartorder:process()
      end
    end
  end
  log:trace("robot stopped")
  if Stop ~= nil then
    Stop()
  end
  log:close()
end

-- TRANSACTION CALLBACK
function OnTransReply(trans_reply)
  local key = trans_reply.trans_id
  local executor = SmartOrder.pool[key]
  if executor ~= nil then
    log:trace("trans status: " .. tostring(trans_reply.status))
    if trans_reply.status == QUIK.TRANS_REPLY.COMPLETE then
      executor.order.number = trans_reply.order_num
    else
      executor.order = nil
    end
  end
end

-- ORDERS CALLBACK
function OnOrder(order)
  local key = order.trans_id
  local executor = SmartOrder.pool[key]
  log:trace("OnOrder key "
            .. tostring(key)
            .. ", flags: "
            .. tostring(order.flags))
  -- there isn't order if was executed immediately
  if executor ~= nil and executor.order ~= nil then
    log:trace("Filled calculation for balance: " .. tostring(order.balance))
    executor.order.filled = order.qty - order.balance
    -- other statuses?
    if bitand(order.flags, QUIK.ORDER_BITMAP.ACTIVE) == 0 then
      log:trace("Inactivating order")
      executor.order.active = false
    end
  end
end

-- INIT CALLBACK
function OnInit(path)
  -- Only there it's possible to take path
  log:open(path)
end

function IsWorking()
  return WORKING_FLAG
end

-- END CALLBACK
function OnStop(stop_flag)
  WORKING_FLAG = false
end
