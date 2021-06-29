describe("hacktrade", function()
  before_each(function()
    dofile("hacktrade.lua")
    stub(log, "open")
    stub(log, "close")
    stub(log, "log")
  end)

  describe("при запуске робота", function()

    before_each(function()
      _G.Robot = nil
      _G.Start = nil
      _G.Stop = nil
      _G.sleep = nil
      _G.sendTransaction = nil
    end)

    it("происходит корректный возврат из Trade()", function()
      local called = false
      _G.Robot = function()
        Trade()
        called = true
      end
      main()
      assert.is.truthy(called)
    end)

    it("Start()/Robot()/Stop() выполняются в нужном порядке", function()
      local calls = {}
      _G.Start = function()
        table.insert(calls, "Start")
      end
      _G.Robot = function()
        table.insert(calls, "Robot")
      end
      _G.Stop = function()
        table.insert(calls, "Stop")
      end
      main()
      assert.are.same(calls, {"Start", "Robot", "Stop"})
    end)

    it("робот завершается при сигнале остановки от quik", function()
      local resumed = false
      _G.Robot = function()
        Trade()
        OnStop(true)
        Trade()
        resumed = true
      end
      main()
      assert.is.falsy(resumed)
    end)
  end)

  describe("при загрузке имеющихся позиций в SmartOrder", function()
    local order

    local trade = function()
      order:load()
    end

    before_each(function()
      _G.getNumberOf = nil
      _G.getItem = nil
      _G.Robot = trade
      _G.getNumberOf = function()
        return 1
      end
      _G.getSecurityInfo = function(class_code, sec_code)
        if class_code == 'TQBR' and sec_code == order.ticker then
          return {
            lot_size = 10
          }
        end
        return nil
      end
    end)

    describe("при работе с неизвестными рынками", function()
      before_each(function()
        order = SmartOrder{
          market = "NO_SUCH_MARKET",
          ticker = "T1",
          account = "A1",
          client = "C1"
        }
      end)

      describe("при загрузке", function()
        it("возникает ошибка", function()
          assert.has_error(function() main() end)
        end)
      end)
    end)

    describe("при работе с акциями", function()
      before_each(function()
        order = SmartOrder{
          market = "TQBR",
          ticker = "T1",
          account = "A1",
          client = "C1"
        }
      end)
      describe("при наличии совпадающих лонгов", function()
        before_each(function()
          _G.getItem = function()
            return {
              sec_code = "T1",
              limit_kind = 2,
              currentbal = 10
            }
          end
          main()
        end)

        it("они загружаются", function()
          assert.are.equal(order.planned, 1)
        end)

        it("filled корректно считается", function()
          assert.is_truthy(order.filled)
        end)
      end)

      describe("при наличии совпадающих шортов", function()
        before_each(function()
          _G.getItem = function()
            return {
              sec_code = "T1",
              limit_kind = 2,
              currentbal = -10
            }
          end
          main()
        end)

        it("они загружаются", function()
          assert.are.equal(order.planned, -1)
        end)

        it("filled корректно считается", function()
          assert.is_truthy(order.filled)
        end)
      end)

    end)

    describe("при работе с фьючами", function()

      before_each(function()
        order = SmartOrder{
          market = "SPBFUT",
          ticker = "T1",
          account = "A1",
          client = "C1"
        }
      end)

      describe("при наличии лонгов", function()
        before_each(function()
          _G.getItem = function()
            return {
              seccode = "T1",
              totalnet = 1
            }
          end
          main()
        end)

        it("они загружаются", function()
          assert.are.equal(order.planned, 1)
        end)

        it("filled корректно считается", function()
          assert.is_truthy(order.filled)
        end)
      end)

      describe("при наличии шортов фьючей", function()
        before_each(function()
          _G.getItem = function()
            return {
              seccode = "T1",
              totalnet = -1
            }
          end
          main()
        end)

        it("они загружаются", function()
          assert.are.equal(order.planned, -1)
        end)

        it("filled корректно считается", function()
          assert.is_truthy(order.filled)
        end)
      end)

      describe("при наличии прочих позиций", function()
        before_each(function()
          _G.getItem = function()
            return {
              seccode = "T2",
              totalnet = 1
            }
          end
          main()
        end)
        it("они игнорируются", function()
          assert.are.equal(order.planned, 0)
        end)
      end)
    end)
  end)

  describe("при создании SmartOrder", function()
    local order
    local trade = function()
      Trade()
    end

    before_each(function()
      order = SmartOrder{
          market = "M1",
          ticker = "T1",
          account = "A1",
          client = "C1",
          max_tries = 2
        }
      order:update(10.0, 2)
      _G.Robot = trade
    end)

    describe("и одновременном срабатывании OnTransReply", function()
      before_each(function()
        _G.sendTransaction = function()
          OnTransReply({
            trans_id = order.trans_id,
            status = 3,
            order_num = 2
          })
        end
        main()
      end)

      it("сохраняется номер заявки", function()
        assert.are.same(2, order.order.number)
      end)
    end)

    describe("и одновременном срабатывании OnTransReply и OnOrder", function()
      before_each(function()
        _G.sendTransaction = function()
          OnTransReply({
            trans_id = order.trans_id,
            status = 3,
            order_num = 2
          })
          OnOrder({
            trans_id = order.trans_id,
            qty = 2,
            balance = 0,
            flags = 0x2
          })
        end
        main()
      end)

      it("order.order деактивируется", function()
          assert.are.same({
            sign = 1.0,
            number = 2,
            price = 10.0,
            quantity = 2,
            active = false,
            filled = 2
          }, order.order)
      end)
    end)

    describe("при вызове ожидания выполнения ордера", function()

      before_each(function()
        _G.Robot = function()
          order:fill()
        end
        _G.sendTransaction = function()
        end
      end)

      describe("при срабатывании в пределах отведенных попыток", function()
        before_each(function()
          _G.sleep = mock(function()
            OnOrder({
              trans_id = order.trans_id,
              qty = 2,
              balance = 0,
              flags = 0x2
            })
          end)
          main()
        end)
        it("fill выполняется", function()
          assert.is_true(order.filled)
        end)
      end)

      describe("при не срабатывании в пределах отведенных попыток", function()
        before_each(function()
          _G.sleep = mock(function()
          end)
        end)
        it("возникает ошибка", function()
          assert.has_error(function() main() end)
          assert.stub(_G.sleep).was.called(2)
        end)
      end)
    end)

    describe("при нулевой цене", function()
      before_each(function()
        order:update(0, nil)
        _G.sendTransaction = mock(function()
          return ""
        end)
        main()
      end)

      it("в терминал уходит заявка по рынку", function()
        assert.stub(_G.sendTransaction).was.called_with({
            ACCOUNT = "A1",
            CLIENT_CODE = "C1",
            CLASSCODE = "M1",
            SECCODE = "T1",
            TYPE = "M",
            TRANS_ID = tostring(order.trans_id),
            ACTION = "NEW_ORDER",
            OPERATION = "B",
            PRICE = tostring(0),
            QUANTITY = tostring(2)
        })
      end)
    end)


    describe("и отсутствии гонок", function()
      before_each(function()
        _G.sendTransaction = mock(function()
          return ""
        end)
        main()
      end)

      it("в терминал уходит заявка", function()
        assert.stub(_G.sendTransaction).was.called_with({
            ACCOUNT = "A1",
            CLIENT_CODE = "C1",
            CLASSCODE = "M1",
            SECCODE = "T1",
            TYPE = "L",
            TRANS_ID = tostring(order.trans_id),
            ACTION = "NEW_ORDER",
            OPERATION = "B",
            PRICE = tostring(10.0),
            QUANTITY = tostring(2)
        })
      end)
      it("обновлено внутреннее состояние", function()
        assert.are.same({
          sign = 1.0,
          price = 10.0,
          quantity = 2,
          active = true,
          filled = 0
        }, order.order)
        assert.are.equal(order.planned, 2)
        assert.are.equal(order.remainder, 2)
        assert.is.falsy(order.filled)
      end)

      -- вызовы OnOrder / OnTransReply могут происходить в любом порядке,
      -- ответ суппорта quik
      -- https://forum.quik.ru/messages/forum10/message24910/topic2839/#message24910

      describe("при OnTransReply с успешным статусом и известным id", function()
        local cancel_tran
        before_each(function()
          OnTransReply({
            trans_id = order.trans_id,
            status = 3,
            order_num = 2
          })
          cancel_tran = {
            ACCOUNT = "A1",
            CLIENT_CODE = "C1",
            CLASSCODE = "M1",
            SECCODE = "T1",
            TRANS_ID = "666",
            ACTION = "KILL_ORDER",
            ORDER_KEY=tostring(order.order.number)
          }
        end)

        it("сохраняется номер заявки", function()
          assert.are.same(2, order.order.number)
        end)

        describe("при увеличении числа лотов", function()
          before_each(function()
            order:update(nil, order.planned + 1)
            main()
          end)

          it("выставляется заявка на отмену", function()
            assert.stub(_G.sendTransaction).was.called_with(cancel_tran)
          end)

          describe("при выполнении заявки на отмену", function()
            before_each(function()
              OnTransReply({
                trans_id = order.trans_id,
                status = 4
              })
            end)

            it("order сносится", function()
              assert.is_nil(order.order)
            end)
          end)
        end)

        describe("при уменьшении числа лотов", function()
          before_each(function()
            order:update(nil, order.planned - 1)
            main()
          end)

          it("выставляется заявка на отмену", function()
            assert.stub(_G.sendTransaction).was.called_with(cancel_tran)
          end)
        end)

        describe("при изменении цены", function()
          before_each(function()
            order:update(order.price + 1, nil)
            main()
          end)

          it("выставляется заявка на отмену", function()
            assert.stub(_G.sendTransaction).was.called_with(cancel_tran)
          end)
        end)

        describe("при последующем успешном OnOrder", function()
          before_each(function()
            OnOrder({
              trans_id = order.trans_id,
              qty = 2,
              balance = 0,
              flags = 0x2
            })
          end)

          it("order.order деактивируется", function()
            assert.are.same({
              sign = 1.0,
              number = 2,
              price = 10.0,
              quantity = 2,
              active = false,
              filled = 2
            }, order.order)
          end)
        end)

        describe("при двух подряд идущих частичных OnOrder", function()
          before_each(function()
            OnOrder({
              trans_id = order.trans_id,
              qty = 2,
              balance = 1,
              flags = 0x2
            })
            OnOrder({
              trans_id = order.trans_id,
              qty = 2,
              balance = 0,
              flags = 0x2
            })
          end)

          it("order снимается", function()
            assert.are.same({
              sign = 1.0,
              price = 10.0,
              number = 2,
              quantity = 2,
              active = false,
              filled = 2
            }, order.order)
          end)
        end)
      end)

      describe("при OnTransReply в неизвестным id", function()
        before_each(function()
          OnTransReply({
            trans_id = order.trans_id + 1,
            status = 3,
            order_num = 2
          })
        end)

        it("order не меняется", function()
          assert.are.same({
            sign = 1.0,
            price = 10.0,
            quantity = 2,
            active = true,
            filled = 0
          }, order.order)
        end)
      end)

      describe("при OnTransReply со статусом отличным от 3", function()
        before_each(function()
          OnTransReply({
            trans_id = order.trans_id,
            status = 2,
            order_num = 2
          })
        end)

        it("order удаляется", function()
          assert.is_nil(order.order)
        end)
      end)

      describe("при OnOrder с полным выполнением", function()
        before_each(function()
          OnOrder({
            trans_id = order.trans_id,
            qty = 2,
            balance = 0,
            flags = 0x2
          })
        end)

        it("order снимается", function()
          assert.are.same({
            sign = 1.0,
            price = 10.0,
            quantity = 2,
            active = false,
            filled = 2
          }, order.order)
        end)

        describe("при последующем пересчете", function()
          before_each(function()
            order:process()
          end)

          it("order.order удаляется", function()
            assert.is_nil(order.order)
          end)

          it("параметры order обновляются", function()
            assert.are.equal(order.position, 2)
            assert.is.truthy(order.filled)
            assert.are.equal(order.remainder, 0)
          end)
        end)

        describe("при последующем успешном OnTransReply", function()
          before_each(function()
            OnTransReply({
              trans_id = order.trans_id,
              status = 3,
              order_num = 2
            })
          end)

          it("сохраняется номер заявки", function()
            assert.are.same(2, order.order.number)
          end)
        end)
      end)

      describe("при OnOrder с частичным выполнением", function()
        before_each(function()
          OnOrder({
            trans_id = order.trans_id,
            qty = 2,
            balance = 1,
            flags = 0x1
          })
        end)

        it("остаток в order уменьшается и order не снимается", function()
          assert.are.same({
            sign = 1.0,
            price = 10.0,
            quantity = 2,
            active = true,
            filled = 1
          }, order.order)
        end)

        describe("при последующем пересчете", function()
          before_each(function()
            order:process()
          end)

          it("order.order остается", function()
            assert.is_not_nil(order.order)
          end)

          it("параметры order не меняются", function()
            assert.are.equal(0, order.position)
            assert.is.falsy(order.filled)
            assert.are.equal(2, order.remainder)
          end)
        end)

        describe("при последующем успешном OnTransReply", function()
          before_each(function()
            OnTransReply({
              trans_id = order.trans_id,
              status = 3,
              order_num = 2
            })
          end)

          it("сохраняется номер заявки", function()
            assert.are.same(2, order.order.number)
          end)
        end)
      end)

      describe("при OnOrder с неизвестным id", function()
        before_each(function()
          OnOrder({
            trans_id = order.trans_id + 1,
            qty = 2,
            balance = 1,
            flags = 0x1
          })
        end)
        it("имеющийся order не меняется", function()
          assert.are.same({
            sign = 1.0,
            price = 10.0,
            quantity = 2,
            active = true,
            filled = 0
          }, order.order)
        end)
      end)
    end)
  end)

  describe("для объекта ServerInfo", function()
    local server
    describe("при запросе любого значения", function()
      before_each(function()
        _G.getInfoParam = mock(function()
        end)
        server = ServerInfo{}
      end)
      it("запрос пробрасывается в getInfoParam", function()
        local _ = server.servertime
        assert.stub(_G.getInfoParam).was.called()
      end)
      it("ключ преобразуется в верхний регистр", function()
        local _ = server.serverTime
        assert.stub(_G.getInfoParam).was.called_with('SERVERTIME')
      end)
    end)
    describe("при найденом ответе", function()
      before_each(function()
        _G.getInfoParam = function()
          return "test"
        end
        server = ServerInfo{}
      end)
      it("он возвращается в неизменном виде", function()
        assert.are.same(server.someValue, "test")
      end)
    end)
    describe("при пустом ответе", function()
      before_each(function()
        _G.getInfoParam = function()
          return ""
        end
        server = ServerInfo{}
      end)
      it("возвращается nil", function()
        assert.is_nil(server.someValue)
      end)
    end)
    describe("при retry_on_empty = true", function()
      before_each(function()
        local c = {called = 0}
        _G.getInfoParam = mock(function()
          c.called = c.called + 1
          if c.called == 1 then
            return nil
          elseif c.called == 2 then
            return ''
          elseif c.called == 3 then
            return 1
          end
        end)
        _G.sleep = mock(function()
        end)
        server = ServerInfo{retry_on_empty = true}
        _ = server.test
      end)
      it("делается повторная попытка", function()
        assert.stub(_G.getInfoParam).was.called(3)
      end)
      it("и делается sleep", function()
        assert.stub(_G.sleep).was.called(2)
      end)
    end)
  end)

  describe("для объекта Indicator", function()
    local indicator
    before_each(function()
      _G.getCandlesByIndex = function(tag, line, first_candle, count)
        local data = {}
        data[0] = {
          {
            open = 1,
            close = 2
          },
          {
            open = 2,
            close = 3
          },
          {
            open = 3,
            close = 4
          }
        }
        data[1] = {
          {
            open = 10,
            close = 20
          },
          {
            open = 20,
            close = 30
          },
          {
            open = 30,
            close = 40
          }
        }
        return data[line], 3, "test"
      end
    end)

    describe("при отдаче данных с 3-й попытки", function()
      before_each(function()
        local c = {called = 0}
        _G.getNumCandles = mock(function()
          c.called = c.called + 1
          if c.called == 3 then
            return 1
          end
          return 0
        end)
        _G.sleep = mock(function()
        end)
      end)

      describe("и дефолтном ограничении на число попыток", function()
        before_each(function()
          indicator = Indicator{tag = "test"}
        end)

        it("они в итоге извлекаются", function()
          local _ = indicator.values[1]
          assert.stub(_G.getNumCandles).was.called(3)
          assert.stub(_G.sleep).was.called(2)
        end)
      end)

      describe("при меньшем числе заданных попыток", function()
        before_each(function()
          indicator = Indicator{tag = "test", max_tries = 2}
        end)

        it("возвращается ошибка", function()
          assert.has_error(function()
            _ = indicator.values[1]
          end)
          assert.stub(_G.getNumCandles).was.called(2)
        end)
      end)
    end)

    describe("при успешном получении данных", function()
      before_each(function()
        _G.getNumCandles = function(tag)
          return 3
        end
        indicator = Indicator{tag = "test"}
      end)

      it("по числовому ключу возвращается close первого индикатора", function()
        assert.are.same(2, indicator[1])
      end)

      it("по ключу values возвращается все атрибуты", function()
        assert.are.same({open = 1, close = 2}, indicator.values[1])
      end)

      it("явный запрос по первому ключу без указания номера линии", function()
        assert.are.equal(2, indicator.closes[1])
        assert.are.equal(1, indicator.opens[1])
      end)

      it("явный запрос по последнему ключу без указания номера линии", function()
        assert.are.equal(4, indicator.closes[3])
        assert.are.equal(3, indicator.opens[3])
      end)

      it("явный запрос по ключу с указанием номера линии", function()
        assert.are.equal(20, indicator.closes_1[1])
        assert.are.equal(10, indicator.opens_1[1])
      end)

      it("по числовому ключу можно запросить данные с конца", function()
        assert.are.same(4, indicator[-1])
      end)

      it("по ключу values можно запросить данные с конца", function()
        assert.are.same({open = 3, close = 4}, indicator.values[-1])
      end)

      it("явный запрос по ключу с конца без указания номера линии", function()
        assert.are.equal(4, indicator.closes[-1])
        assert.are.equal(3, indicator.opens[-1])
      end)

      it("явный запрос по ключу с конца с указанием номера линии", function()
        assert.are.equal(40, indicator.closes_1[-1])
        assert.are.equal(30, indicator.opens_1[-1])
        assert.are.same({open = 30, close = 40}, indicator.values_1[-1])
      end)

      it("запросы по несуществующим индексам", function()
        assert.is_nil(indicator[-100])
        assert.is_nil(indicator[100])
      end)
    end)
  end)

  describe("для объекта MarketData", function()
    local feed

    describe("при непустом стакане", function()
      before_each(function()
        _G.getQuoteLevel2 = function(class_code, sec_code)
          return {
            bid_count = 2,
            offer_count = 3,
            bid = {
              {price = "10.0", quantity = "1"},
              {price = "11.0", quantity = "2"}
            },
            offer = {
              {price = "12.0", quantity = "1"},
              {price = "13.0", quantity = "2"},
              {price = "14.0", quantity = "3"}
            }
          }
        end
        _G.getParamEx = function(class_code, sec_code, param_name)
          return {param_type = 3, param_value = "ok"}
        end
        feed = MarketData{
          market = "M1",
          ticker = "T1"
        }
      end)

      it("по ключу bids убывающая таблица числовых бидов", function()
        assert.are.same({
          {price = 11.0, quantity = 2},
          {price = 10.0, quantity = 1}
        }, feed.bids)
      end)

      it("по ключу offers возрастающая таблица числовых оферов", function()
        assert.are.same({
          {price = 12.0, quantity = 1},
          {price = 13.0, quantity = 2},
          {price = 14.0, quantity = 3}
        }, feed.offers)
      end)

      it("по прочим ключам запрос адресуется в getParamEx", function()
        assert.are.equal("ok", feed.test)
      end)
    end)

    describe("при пустом стакане", function()
      before_each(function()
        _G.getQuoteLevel2 = function(class_code, sec_code)
          return {
            bid_count = 0,
            offer_count = 0,
            bid = nil,
            offer = nil
          }
        end
        _G.getParamEx = function(class_code, sec_code, param_name)
          return {}
        end
        feed = MarketData{
          market = "M1",
          ticker = "T1"
        }
      end)

      it("по ключу bids отдается {}", function()
        assert.are.same({}, feed.bids)
      end)

      it("по ключу offers отдается {}", function()
        assert.are.same({}, feed.offers)
      end)

      it("по прочим ключам отдается nil", function()
        assert.is_nil(feed.test)
      end)
    end)
  end)
end)
