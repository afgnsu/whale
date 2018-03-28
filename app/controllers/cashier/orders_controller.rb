class Cashier::OrdersController < Cashier::BaseController
  before_action :set_order, only: [:show, :pick_up, :edit, :set_member, :update,
                                   :new_guest, :create_guest, ]

  def index
    @orders = Order.all
  end

  def not_pick
    @orders = Order.where('status ==?',false)
  end

  def pick_up
    @order = Order.find(params[:id])
    @order.order_items.each do |item|
      product = item.product
      product.quantity -= item.quantity
      if product.quantity <= 0
        flash[:alert] = "商品庫存數量錯誤."
      end

      stock_record = product.stock_records.build(quantity: -item.quantity,order_id: @order.id)
      stock_record.save!
    end
    @order.status = true
    @order.save!
    flash[:notice] = "訂單取貨成功"
    redirect_to not_pick_cashier_orders_path
  end

  def new_guest
    @guest = Guest.new

  end

  def create_guest
    @guest = Guest.new(guest_params)
    @guest.user_id = current_user.id
    @guest.save!

    @order.guest_id = @guest.id
    @order.save!
    flash[:notice] = "訂單新增客情成功"
    redirect_to cashier_orders_path
  end

  def edit
    @order_items = @order.order_items
    current_cart.cart_items.destroy_all
    @order_items.each do |item|
      @cart_item = current_cart.cart_items.build(product_id: item.product.id, quantity: item.quantity)
      @cart_item.discount_off = item.price
      discount_method = DiscountMethod.find_by(content: "優惠價")
      @cart_item.discount_method_code = discount_method.code
      @cart_item.save!
    end

    @index_hash = Hash.new(0)
    @coupon = Product.find_by(zh_name: "折價卷")
    @cart_coupons = current_cart.cart_items.where('product_id = ?',@coupon.id)
    @cart_items = current_cart.cart_items.where('product_id != ?',@coupon.id)
    @products = Product.where('id != ?',@coupon.id) 
    @coupon_discount = 0
    @cart_coupons.each do |c|
      @coupon_discount += c.discount_off
    end
    if params[:member_id] != nil
      @member = Member.find(params[:member_id])
    elsif @order.member_id != -1
      @member = Member.find(@order.member_id)
    else
      @member = Member.new(id: -1)
    end
  end


  def show
    @orders = Order.where(member_id: @order.member_id)
  end


  def set_member  

    @member = Member.new
  end

  def new
    @order = Order.new(member_id: params[:id])
    @coupon = Product.find_by(zh_name: "折價卷")
    @index_hash = Hash.new(0)
    @order.amount = 0
    @order.discount_off = 100
    @products = Product.where('id != ?',@coupon.id) 
    @cart_items = current_cart.cart_items.where('product_id != ?',@coupon.id)
    @cart_coupons = current_cart.cart_items.where('product_id = ?',@coupon.id)
    @coupon_discount = 0
    @cart_coupons.each do |c|
      @coupon_discount += c.discount_off
    end

    if params[:id] != "-1"
      @member = Member.find(params[:id])
      @order.name = @member.name
      @order.phone = @member.phone
      @order.address = @member.address
    else
      @member = Member.new(id: -1)
    end

  end

  def update
    #復原原本訂單扣的庫存
    @order.order_items.each do |item|
      product = item.product
      if product.zh_name != "折價卷" && @order.status && @order.address == "local"
        product.quantity += item.quantity
        product.save!
      end
      
    end

    if @order.update(order_params)
      current_cart.cart_items.each do |item|
        product = item.product
        if product.zh_name != "折價卷" && @order.status && @order.address == "local"
          product.quantity -= item.quantity
          if product.quantity <= 0
            flash[:alert] = "商品庫存數量錯誤."
          end

          stock_record = product.stock_records.find_by(order_id: @order.id)
          if stock_record == nil
            stock_record = product.stock_records.build(quantity: -item.quantity,order_id: @order.id)
          else
            stock_record.quantity -= item.quantity
          end
          stock_record.save!
        end
        
        order_item = @order.order_items.find_by(product_id: item.product.id)
        if order_item == nil
          order_item = @order.order_items.build(product_id: item.product.id, price: item.calculate, quantity: item.quantity)
        else
          order_item.update(price: item.calculate, quantity: item.quantity)
        end
        
        order_item.save!
        product.save!
      end
      
      @order.status =  (@order.status || @order.address != "local")
      flash[:notice] = "成功更新訂單記錄"
      redirect_to cashier_orders_path
    else
      flash[:alert] = @guest.errors.full_messages.to_sentence
      
    end
  end

  def create
    if current_cart.cart_items.size ==0
      flash[:alert] = "訂單內容不能是空的"
      @products = Product.all 
      @cart_items = current_cart.cart_items.all
      @member =  order_params[:member_id]=="-1" ? Member.new(id: -1) : Member.find(order_params[:member_id])
      @order =Order.new(member_id: params[:id])
      @order.amount = 0
      redirect_to new_cashier_order_path(id: -1)
    else
      @order = current_user.orders.build(order_params)
      today = Date.today.to_s
      today.slice!("2")
      @order.sn = today.tr('-','').to_i * 1000 + current_cart.id
      current_cart.cart_items.each do |item|
        product = item.product
        if product.zh_name != "折價卷" && @order.status && @order.address == "local"
          product.quantity -= item.quantity
          if product.quantity <= 0
            flash[:alert] = "商品庫存數量錯誤."
          end

          stock_record = product.stock_records.find_by(order_id: @order.id)
          if stock_record == nil
            stock_record = product.stock_records.build(quantity: -item.quantity,order_id: @order.id)
          else
            stock_record.quantity -= item.quantity
          end
          stock_record.save!
        end


        order_item = @order.order_items.build(product_id: item.product.id, price: item.calculate, quantity: item.quantity)
        order_item.save!
        product.save!
      end
      
      @order.status =  (@order.status || @order.address != "local")
      if @order.save
        session[:cart_id] = nil
        #當訂單為宅配時寄信通知倉庫
        if @order.address != "local"
          UserMailer.notify_order_deliver(@order).deliver_now!
        end
        flash[:notice] = "成功成立訂單"
        redirect_to new_guest_cashier_order_path(@order)
      else
        flash[:alert] = @order.errors.full_messages.to_sentence
        redirect_to new_cashier_order_path(id: order_params[:member_id])
      end

      
    end
    
  end

  def sales_analysis_day

  end

  def search_outcome
    if params[:type] == "statement"
      s_date = Date.parse(params[:s_date]).to_time
      e_date = Date.parse(params[:e_date]).to_time
      puts s_date
      puts e_date
      @orders = Order.where(created_at: s_date.beginning_of_day..e_date.end_of_day).order(created_at: :asc)

      render :json =>  @orders.to_json(:include => [:user])
    else
      date = Date.parse(params[:created_at]+'-01').to_time
      puts date
      orders = Order.where(created_at: date.all_month)
   
    
    # @orders = Order.where("created_at >= ?", Time.zone.now.beginning_of_day)

    sum = []
    orders.each do |order|
      order_items = order.order_items

      sum.concat(order_items)
      puts sum
    end
    total = sum.sort_by { |k| k["product_id"] }
    @total_uni = total.uniq{|t| t["product_id"]}

    mix_arr_1 = total.pluck(:product_id, :quantity).sort!
    @order_item_hash = Hash.new(0)
    mix_arr_1.each {|key, value| @order_item_hash[key] += value}
    puts @order_item_hash

    # 另外抓商品價格pluck(:product_id, :price)
    mix_arr_2 = total.pluck(:product_id, :price).sort!
    @order_item_price_hash = Hash.new(0)
    mix_arr_2.each {|key, value| @order_item_price_hash[key] += value}
    puts @order_item_price_hash

    @products = Array.new()
    @total_uni.each do |item|
      @products  << item.product
    end

    all_price = total.pluck(:price)
    @total_price = all_price.inject(0){|sum,x| sum + x }

    #puts @products[0]
    render :json => {:total_uni =>@total_uni, :order_item_hash => @order_item_hash, :products => @products, :order_item_price_hash => @order_item_price_hash, :total_price => @total_price}
    end
  end

  def sales_analysis_statement
    @orders = Order.all
  end


  def ranking_product
    date = Date.today.all_month
    @orders = Order.where(created_at: date)

    sum = []
    @orders.each do |order|
      order_items = order.order_items

      sum.concat(order_items)
      puts sum
    end
    total = sum.sort_by { |k| k["product_id"] }
    total_uni = total.uniq{|t| t["product_id"]}

    mix_arr_1 = total.pluck(:product_id, :quantity).sort!
    order_item_hash = Hash.new(0)
    mix_arr_1.each {|key, value| order_item_hash[key] += value}

    puts order_item_hash

    product_ranking = order_item_hash.sort_by{ |k, v| v }.reverse.transpose.first
    @product_quantity = order_item_hash.sort_by{ |k, v| v }.reverse.transpose.last
    @all = total_uni.sort_by {|e| product_ranking.index(e.product_id) }

    # chart
    @products = Array.new()
    total_uni.each do |order|
    @products  << order.product.zh_name

    puts @products
    end

    @y = order_item_hash.sort_by{ |k, v| k }.transpose.last
  end

  def ranking_user
    date = Date.today.all_month
    @orders = Order.where(created_at: date)

    total = @orders.sort_by { |k| k["user_id"] }
    total_uni = total.uniq{|t| t["user_id"]}

    mix_arr_1 = total.pluck(:user_id, :amount).sort!
    order_user_hash = Hash.new(0)
    mix_arr_1.each {|key, value| order_user_hash[key] += value}
    puts @order_user_hash

    user_ranking = order_user_hash.sort_by{ |k, v| v }.reverse.transpose.first
    @user_amount = order_user_hash.sort_by{ |k, v| v }.reverse.transpose.last
    @all = total_uni.sort_by {|e| user_ranking.index(e.user_id) }
  
  # chart
    @users = Array.new()
    total_uni.each do |order|
    @users  << order.user.name

    puts @users
    end

    @y = order_user_hash.sort_by{ |k, v| k }.transpose.last
  end

  def ranking_hour
    @orders = Order.where("created_at >= ?", Time.zone.now.beginning_of_day)
    total = @orders.sort_by {  |s| s.created_at.hour }
    mix_arr_1 = total.pluck(:created_at, :amount)

    @hour_amount_hash = Hash.new(0)
    mix_arr_1.each {|key, value| @hour_amount_hash[key.hour] += value}
    puts @hour_amount_hash

    @arr_x = [10,11,12,13,14,15,16,17,18,19,20,21,22]
    @arr_y = [0,0,0,0,0,0,0,0,0,0,0,0,0]
    @arr_y2 = [0,0,0,0,0,0,0,0,0,0,0,0,0]
  end

  private

  def order_params
    params.require(:order).permit(:member_id, :payment_method, :address,
                                  :phone, :name, :remark,
                                  :amount, :discount_off, :status,
                                  :user_id, :created_at)
  end
  
  def guest_params
    params.require(:guest).permit(:payment, :gender, :guest_type_id, :country_id, :age_id, :info_way_id, :user_id, :remark)
  end

  def set_order
    @order = Order.find(params[:id])
  end
end
