import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

// ==========================================
// 1. MAIN FUNCTION & KONFIGURASI
// ==========================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: MaterialApp(
        title: 'Cemilkuy',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: const Color(0xFFFF7F50),
          scaffoldBackgroundColor: const Color(0xFFF4F7F6),
          colorScheme: ColorScheme.fromSwatch().copyWith(
            primary: const Color(0xFFFF7F50),
            secondary: const Color(0xFFFFDB58),
          ),
          useMaterial3: true,
          fontFamily: 'OpenSans',
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => Provider.of<AuthProvider>(context, listen: false).fetchUser());
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (auth.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (auth.currentUser == null) return const AuthScreen();
    
    if (auth.currentUser!.role == 'seller' || auth.currentUser!.role == 'admin') {
      return const SellerDashboard();
    } else {
      return const HomeScreen();
    }
  }
}

// ==========================================
// 2. WIDGET HELPER
// ==========================================
class CemilkuyImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const CemilkuyImage({super.key, required this.imageUrl, this.width, this.height, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return _placeholder();
    if (imageUrl.startsWith('http')) {
      return Image.network(imageUrl, width: width, height: height, fit: fit, errorBuilder: (c, e, s) => _placeholder());
    } else {
      try {
        return Image.memory(base64Decode(imageUrl), width: width, height: height, fit: fit, errorBuilder: (c, e, s) => _placeholder());
      } catch (e) { return _placeholder(); }
    }
  }

  Widget _placeholder() {
    return Container(width: width, height: height, color: Colors.grey[200], child: const Icon(Icons.image, color: Colors.grey));
  }
}

String formatDate(DateTime? date) {
  if (date == null) return "-";
  return "${date.day}/${date.month}/${date.year}";
}

// ==========================================
// 3. MODELS & PROVIDERS
// ==========================================

class UserModel {
  final String uid, name, email, phone, role;
  final String? shopName;
  final double balance;
  UserModel({required this.uid, required this.name, required this.email, required this.phone, required this.role, this.shopName, this.balance = 0});

  factory UserModel.fromMap(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'member',
      shopName: data['shopName'],
      balance: (data['balance'] ?? 0).toDouble(),
    );
  }
}

class ProductModel {
  final String id, sellerId, shopName, name, category, description, imageUrl;
  final int price, stock;
  final DateTime? prodDate;
  final DateTime? expDate;

  ProductModel({
    required this.id, required this.sellerId, required this.shopName, required this.name, 
    required this.category, required this.price, required this.stock, required this.description, 
    required this.imageUrl, this.prodDate, this.expDate
  });

  factory ProductModel.fromSnapshot(DocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    return ProductModel(
      id: doc.id,
      sellerId: data['sellerId'],
      shopName: data['shopName'] ?? 'Toko',
      name: data['name'],
      category: data['category'],
      price: data['price'],
      stock: data['stock'],
      description: data['description'],
      imageUrl: data['imageUrl'] ?? '',
      prodDate: data['prodDate'] != null ? (data['prodDate'] as Timestamp).toDate() : null,
      expDate: data['expDate'] != null ? (data['expDate'] as Timestamp).toDate() : null,
    );
  }
}

class CartItem {
  final ProductModel product;
  int quantity;
  CartItem({required this.product, this.quantity = 1});
}

class AuthProvider with ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = true;
  List<String> _favorites = []; 

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  List<String> get favorites => _favorites;

  Future<void> fetchUser() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        _currentUser = UserModel.fromMap(doc.data() as Map<String, dynamic>, user.uid);
        var favSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('favorites').get();
        _favorites = favSnapshot.docs.map((e) => e.id).toList();
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> toggleFavorite(String productId) async {
    if (_currentUser == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).collection('favorites').doc(productId);
    
    if (_favorites.contains(productId)) {
      await ref.delete();
      _favorites.remove(productId);
    } else {
      await ref.set({'addedAt': FieldValue.serverTimestamp()});
      _favorites.add(productId);
    }
    notifyListeners();
  }

  bool isFavorite(String productId) => _favorites.contains(productId);

  Future<String?> login(String email, String password) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      await fetchUser();
      return null;
    } catch (e) { return e.toString(); }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    _currentUser = null;
    _favorites = [];
    notifyListeners();
  }
}

class CartProvider with ChangeNotifier {
  List<CartItem> _items = [];
  List<CartItem> get items => _items;
  double get totalAmount => _items.fold(0, (sum, item) => sum + (item.product.price * item.quantity));
  String? get currentShopName => _items.isNotEmpty ? _items.first.product.shopName : null;
  String? get currentSellerId => _items.isNotEmpty ? _items.first.product.sellerId : null;

  void addToCart(ProductModel product) {
    if (_items.isNotEmpty && _items.first.product.sellerId != product.sellerId) {
      throw Exception("TIDAK BISA CAMPUR TOKO!\nKeranjang berisi produk dari ${_items.first.product.shopName}.");
    }
    int index = _items.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      if (_items[index].quantity < product.stock) _items[index].quantity++;
    } else {
      _items.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void removeSingleItem(String productId) {
    int index = _items.indexWhere((item) => item.product.id == productId);
    if (index >= 0) {
      if (_items[index].quantity > 1) _items[index].quantity--; else _items.removeAt(index);
      notifyListeners();
    }
  }
  void clearCart() { _items = []; notifyListeners(); }
}

// ==========================================
// 4. SCREENS
// ==========================================

// --- AUTH SCREEN ---
class AuthScreen extends StatefulWidget { const AuthScreen({super.key}); @override State<AuthScreen> createState() => _AuthScreenState(); }
class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true; bool isSellerRegister = false;
  final _formKey = GlobalKey<FormState>();
  String _email='', _password='', _name='', _phone='', _shopName='';
  bool _isLoading = false;

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      if (isLogin) {
        String? err = await auth.login(_email, _password);
        if (err != null) throw err;
      } else {
        UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: _email, password: _password);
        await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
          'name': _name, 'email': _email, 'phone': _phone, 'role': isSellerRegister ? 'seller' : 'member',
          'shopName': isSellerRegister ? _shopName : null, 'balance': 0, 'createdAt': FieldValue.serverTimestamp(),
        });
        await auth.fetchUser();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    } finally { if(mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFF7F50), Color(0xFFFF9F43)])),
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(25),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(isLogin ? "Login Cemilkuy" : "Daftar Akun", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    if (!isLogin) ...[
                      TextFormField(decoration: const InputDecoration(labelText: 'Nama Lengkap'), onSaved: (v)=>_name=v!, validator: (v)=>v!.isEmpty?'Isi nama':null),
                      TextFormField(decoration: const InputDecoration(labelText: 'Nomor WA (628xx)'), keyboardType: TextInputType.phone, onSaved: (v)=>_phone=v!, validator: (v)=>v!.isEmpty?'Isi WA':null),
                      if(isSellerRegister) TextFormField(decoration: const InputDecoration(labelText: 'Nama Toko'), onSaved: (v)=>_shopName=v!, validator: (v)=>v!.isEmpty?'Isi Toko':null),
                    ],
                    TextFormField(decoration: const InputDecoration(labelText: 'Email'), onSaved: (v)=>_email=v!, validator: (v)=>!v!.contains('@')?'Email salah':null),
                    TextFormField(decoration: const InputDecoration(labelText: 'Password'), obscureText:true, onSaved: (v)=>_password=v!, validator: (v)=>v!.length<6?'Min 6 huruf':null),
                    const SizedBox(height: 20),
                    _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _submit, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7F50), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), child: Text(isLogin ? "Masuk" : "Daftar")),
                    TextButton(onPressed: () => setState(() => isLogin = !isLogin), child: Text(isLogin ? "Belum punya akun? Daftar" : "Sudah punya akun? Login")),
                    if(!isLogin) TextButton(onPressed: () => setState(() => isSellerRegister = !isSellerRegister), child: Text(isSellerRegister ? "Daftar sebagai Member" : "Ingin Jualan? Buka Toko")),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- HOME SCREEN (PEMBELI) ---
class HomeScreen extends StatefulWidget { const HomeScreen({super.key}); @override State<HomeScreen> createState() => _HomeScreenState(); }
class _HomeScreenState extends State<HomeScreen> {
  String selectedCategory = 'All';
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Cemilkuy", style: TextStyle(color: Color(0xFFFF7F50), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.history), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())), tooltip: "Riwayat Pesanan"),
          Stack(children: [
            IconButton(icon: const Icon(Icons.shopping_bag_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen()))),
            if (cart.items.isNotEmpty) Positioned(right: 5, top: 5, child: CircleAvatar(radius: 8, backgroundColor: Colors.red, child: Text('${cart.items.length}', style: const TextStyle(fontSize: 10, color: Colors.white))))
          ]),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => auth.logout()),
        ],
      ),
      body: Column(
        children: [
          Container(width: double.infinity, height: 100, margin: const EdgeInsets.all(15), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF7F50), Color(0xFFFFDB58)]), borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.all(20), child: const Center(child: Text("🔥 Jajanan Hits Kampus\nTeman Ngunyah Paling Asik!", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: TextField(
              onChanged: (val) => setState(() => searchQuery = val.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Cari cemilan...",
                prefixIcon: const Icon(Icons.search),
                filled: true, fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none)
              ),
            ),
          ),
          const SizedBox(height: 10),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(children: ['All', 'Pedas', 'Manis', 'Asin', 'Favorit'].map((cat) {
              return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(cat), selected: selectedCategory == cat, onSelected: (val) => setState(() => selectedCategory = cat), selectedColor: const Color(0xFFFF7F50), backgroundColor: Colors.white, labelStyle: TextStyle(color: selectedCategory == cat ? Colors.white : Colors.black)));
            }).toList()),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('products').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                var products = snapshot.data!.docs.map((doc) => ProductModel.fromSnapshot(doc)).toList();
                
                if (selectedCategory == 'Favorit') {
                  products = products.where((p) => Provider.of<AuthProvider>(context).isFavorite(p.id)).toList();
                } else if (selectedCategory != 'All') {
                  products = products.where((p) => p.category == selectedCategory).toList();
                }
                
                if (searchQuery.isNotEmpty) {
                  products = products.where((p) => p.name.toLowerCase().contains(searchQuery)).toList();
                }

                if (products.isEmpty) return const Center(child: Text("Tidak ada produk."));

                return GridView.builder(
                  padding: const EdgeInsets.all(15),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.65, crossAxisSpacing: 15, mainAxisSpacing: 15),
                  itemCount: products.length,
                  itemBuilder: (ctx, i) => ProductCard(product: products[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- PRODUCT CARD (PEMBELI) ---
class ProductCard extends StatelessWidget {
  final ProductModel product;
  const ProductCard({super.key, required this.product});

  void _chatSeller(BuildContext context) async {
    var doc = await FirebaseFirestore.instance.collection('users').doc(product.sellerId).get();
    if(doc.exists) {
      String phone = doc['phone'];
      if(phone.startsWith('0')) phone = '62${phone.substring(1)}';
      String msg = "Halo, saya tertarik dengan produk *${product.name}* di Cemilkuy.";
      String url = "https://wa.me/$phone?text=${Uri.encodeComponent(msg)}";
      try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (e) { /* ignore */ }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isFav = auth.isFavorite(product.id);

    return Card(
      elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                SizedBox(width: double.infinity, height: double.infinity, child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(15)), child: CemilkuyImage(imageUrl: product.imageUrl))),
                Positioned(top: 5, right: 5, child: CircleAvatar(backgroundColor: Colors.white, radius: 15, child: IconButton(padding: EdgeInsets.zero, icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: Colors.red, size: 20), onPressed: () => auth.toggleFavorite(product.id)))),
                Positioned(bottom: 5, left: 5, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)), child: Text("Stok: ${product.stock}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))))
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text("Exp: ${formatDate(product.expDate)}", style: const TextStyle(fontSize: 10, color: Colors.red)),
              Text("Rp ${product.price}", style: const TextStyle(color: Color(0xFFFF7F50), fontWeight: FontWeight.bold)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                InkWell(onTap: () => _chatSeller(context), child: const Icon(Icons.chat_bubble_outline, size: 20, color: Colors.blue)),
                GestureDetector(
                  onTap: () {
                    try { Provider.of<CartProvider>(context, listen: false).addToCart(product); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Masuk keranjang!"), duration: Duration(milliseconds: 500))); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); }
                  },
                  child: const Icon(Icons.add_circle, color: Colors.green),
                )
              ])
            ]),
          )
        ],
      ),
    );
  }
}

// --- CART & CHECKOUT (DENGAN ALAMAT) ---
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final TextEditingController _addressController = TextEditingController();

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Keranjang Jajan")),
      body: cart.items.isEmpty 
        ? const Center(child: Text("Keranjang kosong")) 
        : Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: cart.items.length, 
                  itemBuilder: (ctx, i) {
                    CartItem item = cart.items[i];
                    return ListTile(
                      leading: SizedBox(width: 50, height: 50, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CemilkuyImage(imageUrl: item.product.imageUrl))),
                      title: Text(item.product.name), 
                      subtitle: Text("Rp ${item.product.price} x ${item.quantity}"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min, 
                        children: [
                          IconButton(icon: const Icon(Icons.remove), onPressed: () => cart.removeSingleItem(item.product.id)), 
                          Text('${item.quantity}'), 
                          IconButton(icon: const Icon(Icons.add), onPressed: () => cart.addToCart(item.product))
                        ]
                      ),
                    );
                  }
                )
              ),
              Container(
                padding: const EdgeInsets.all(20), 
                decoration: BoxDecoration(
                  color: Colors.white, 
                  boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 10)]
                ),
                child: Column(
                  children: [
                    // INPUT ALAMAT
                    TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Alamat Pengiriman Lengkap',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on)
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 15),
                    ElevatedButton(
                      onPressed: () => _checkout(context, cart, user!, _addressController.text), 
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), 
                      child: Text("Checkout Rp ${cart.totalAmount.toInt()} via WA")
                    )
                  ]
                )
              )
            ],
          ),
    );
  }

  void _checkout(BuildContext context, CartProvider cart, UserModel user, String address) async {
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mohon isi alamat pengiriman!")));
      return;
    }

    String sellerId = cart.currentSellerId!;
    var doc = await FirebaseFirestore.instance.collection('users').doc(sellerId).get();
    String phone = doc['phone']; 
    if(phone.startsWith('0')) phone = '62${phone.substring(1)}';
    
    // Simpan Order dengan Alamat
    await FirebaseFirestore.instance.collection('orders').add({
      'buyerId': user.uid, 
      'buyerName': user.name, 
      'sellerId': sellerId, 
      'shopName': cart.currentShopName,
      'address': address, // Simpan Alamat ke Database
      'totalPrice': cart.totalAmount, 
      'status': 'pending', 
      'date': FieldValue.serverTimestamp(),
      'items': cart.items.map((i) => {'name': i.product.name, 'qty': i.quantity, 'price': i.product.price}).toList()
    });

    // Update Total Stok
    for (var item in cart.items) {
      FirebaseFirestore.instance.collection('products').doc(item.product.id).update({
        'stock': FieldValue.increment(-item.quantity)
      });
    }

    // Pesan WhatsApp dengan Alamat
    String msg = "Halo *${cart.currentShopName}*, saya *${user.name}* mau pesan:\n";
    for(var item in cart.items) msg += "- ${item.product.name} (${item.quantity}x)\n";
    msg += "\nTotal: Rp ${cart.totalAmount.toInt()}";
    msg += "\n\n📍 *Alamat Pengiriman:*\n$address";
    msg += "\n\nMohon diproses ya!";

    cart.clearCart(); 
    if(mounted) Navigator.pop(context);
    try { await launchUrl(Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(msg)}"), mode: LaunchMode.externalApplication); } catch (e) {/*ignore*/}
  }
}

// --- RIWAYAT PESANAN (DENGAN ALAMAT) ---
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = Provider.of<AuthProvider>(context, listen: false).currentUser!.uid;
    return Scaffold(
      appBar: AppBar(title: const Text("Riwayat Pesanan")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders')
            .where('buyerId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var orders = snapshot.data!.docs;
          if (orders.isEmpty) return const Center(child: Text("Belum ada riwayat."));
          
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (ctx, i) {
              var data = orders[i].data() as Map<String, dynamic>;
              List items = data['items'] ?? [];
              String itemStr = items.map((e) => "${e['name']} (${e['qty']}x)").join(", ");
              String status = data['status'] ?? 'pending';
              String address = data['address'] ?? '-';
              
              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  title: Text(data['shopName'] ?? 'Toko', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("$itemStr\nTotal: Rp ${data['totalPrice']}\nAlamat: $address"), // Tampilkan Alamat
                  isThreeLine: true,
                  trailing: Text(status == 'completed' ? 'Selesai' : 'Diproses', style: TextStyle(color: status == 'completed' ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --- SELLER DASHBOARD (DENGAN ALAMAT) ---
class SellerDashboard extends StatelessWidget {
  const SellerDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    return DefaultTabController(length: 3, child: Scaffold(
      appBar: AppBar(
        title: Text("Toko ${user.shopName}"), backgroundColor: const Color(0xFFFF7F50), foregroundColor: Colors.white, 
        bottom: const TabBar(labelColor: Colors.white, unselectedLabelColor: Colors.white70, tabs: [
          Tab(text: "Produk"), Tab(text: "Pesanan"), Tab(text: "Laporan")
        ]), 
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => Provider.of<AuthProvider>(context, listen: false).logout())]
      ),
      body: TabBarView(children: [
        
        // TAB 1: CRUD PRODUK
        Scaffold(
          floatingActionButton: FloatingActionButton(backgroundColor: const Color(0xFFFF7F50), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())), child: const Icon(Icons.add, color: Colors.white)),
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('products').where('sellerId', isEqualTo: user.uid).snapshots(), 
            builder: (c, s) {
              if (s.hasError) return Center(child: Text("Error: ${s.error}"));
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              var prods = s.data!.docs.map((d) => ProductModel.fromSnapshot(d)).toList();
              if(prods.isEmpty) return const Center(child: Text("Belum ada produk"));

              return ListView.builder(itemCount: prods.length, itemBuilder: (c, i) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: SizedBox(width: 50, child: CemilkuyImage(imageUrl: prods[i].imageUrl)), 
                  title: Text(prods[i].name), 
                  subtitle: Text("Stok: ${prods[i].stock}\nExp: ${formatDate(prods[i].expDate)}"), 
                  isThreeLine: true,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddProductScreen(product: prods[i])))),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                      showDialog(context: context, builder: (ctx) => AlertDialog(
                        title: const Text("Hapus Produk?"), content: const Text("Data tidak bisa dikembalikan."),
                        actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Batal")), TextButton(onPressed: () { FirebaseFirestore.instance.collection('products').doc(prods[i].id).delete(); Navigator.pop(ctx); }, child: const Text("Hapus", style: TextStyle(color: Colors.red)))]
                      ));
                    })
                  ]),
                ),
              ));
            }
          )
        ),

        // TAB 2: PESANAN (TAMPIL ALAMAT)
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('orders')
              .where('sellerId', isEqualTo: user.uid)
              .snapshots(), 
          builder: (c, s) {
            if (s.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("Error: ${s.error}")));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            var orders = s.data!.docs;
            if(orders.isEmpty) return const Center(child: Text("Belum ada pesanan"));

            return ListView.builder(itemCount: orders.length, itemBuilder: (c, i) {
              var d = orders[i].data() as Map<String, dynamic>;
              String status = d['status'] ?? 'pending';
              String address = d['address'] ?? 'Tidak ada alamat';

              return Card(
                margin: const EdgeInsets.all(10), 
                child: ListTile(
                  title: Text(d['buyerName'] ?? 'Pembeli'), 
                  subtitle: Text("Total: Rp ${d['totalPrice']}\nAlamat: $address"), // Penjual melihat alamat
                  isThreeLine: true,
                  trailing: status=='pending' 
                    ? ElevatedButton(onPressed: () => FirebaseFirestore.instance.collection('orders').doc(orders[i].id).update({'status':'completed'}), child: const Text("Selesai")) 
                    : const Icon(Icons.check_circle, color: Colors.green)
                )
              );
            });
          }
        ),

        // TAB 3: LAPORAN
        _DailyReportTab(sellerId: user.uid)
      ]),
    ));
  }
}

class _DailyReportTab extends StatelessWidget {
  final String sellerId;
  const _DailyReportTab({required this.sellerId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').where('sellerId', isEqualTo: sellerId).where('status', isEqualTo: 'completed').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var allOrders = snapshot.data!.docs;
        DateTime now = DateTime.now();
        double todayIncome = 0; int todayItems = 0;
        
        for (var doc in allOrders) {
          var data = doc.data() as Map<String, dynamic>;
          if(data['date'] != null) {
            DateTime date = (data['date'] as Timestamp).toDate();
            if (date.year == now.year && date.month == now.month && date.day == now.day) {
              todayIncome += (data['totalPrice'] ?? 0);
              List items = data['items'] ?? [];
              for(var item in items) todayItems += (item['qty'] as int);
            }
          }
        }
        return Center(child: Card(margin: const EdgeInsets.all(20), child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Laporan Penjualan Hari Ini", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10), Text(formatDate(now), style: const TextStyle(color: Colors.grey)),
          const Divider(height: 30),
          Text("Rp ${todayIncome.toInt()}", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green)),
          const SizedBox(height: 10), Text("$todayItems Pcs Terjual", style: const TextStyle(fontSize: 18, color: Colors.blue))
        ]))));
      },
    );
  }
}

// --- ADD & EDIT PRODUCT SCREEN (CRUD) ---
class AddProductScreen extends StatefulWidget { 
  final ProductModel? product; 
  const AddProductScreen({super.key, this.product}); 
  @override _AddProductScreenState createState() => _AddProductScreenState(); 
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _key = GlobalKey<FormState>(); 
  String _name='', _cat='Pedas', _desc=''; 
  int _price=0, _stock=0; 
  File? _imgFile; String? _existingImageUrl;
  bool _load=false;
  DateTime? _prodDate, _expDate;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _name = widget.product!.name; _cat = widget.product!.category; _price = widget.product!.price;
      _stock = widget.product!.stock; _desc = widget.product!.description; _existingImageUrl = widget.product!.imageUrl;
      _prodDate = widget.product!.prodDate; _expDate = widget.product!.expDate;
    }
  }

  Future<void> _pick() async { final p = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 50, maxWidth: 600); if(p!=null) setState(()=>_imgFile=File(p.path)); }
  Future<void> _selectDate(bool isProd) async {
    DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
    if (picked != null) setState(() { if (isProd) _prodDate = picked; else _expDate = picked; });
  }

  void _save() async {
    if(!_key.currentState!.validate()) return;
    if(_imgFile == null && _existingImageUrl == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Foto wajib ada!"))); return; }
    if(_prodDate == null || _expDate == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Isi tanggal!"))); return; }
    _key.currentState!.save(); setState(()=>_load=true);
    try {
      final u = Provider.of<AuthProvider>(context, listen: false).currentUser!;
      String finalImg = _existingImageUrl ?? '';
      if (_imgFile != null) {
        List<int> bytes = await _imgFile!.readAsBytes();
        if(bytes.length > 900000) throw "Gambar terlalu besar.";
        finalImg = base64Encode(bytes);
      }
      
      Map<String, dynamic> data = {
        'name': _name, 'category': _cat, 'price': _price, 'stock': _stock, 'description': _desc, 'imageUrl': finalImg,
        'prodDate': Timestamp.fromDate(_prodDate!), 'expDate': Timestamp.fromDate(_expDate!)
      };

      if (widget.product == null) {
        data['sellerId'] = u.uid; data['shopName'] = u.shopName; data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('products').add(data);
      } else {
        await FirebaseFirestore.instance.collection('products').doc(widget.product!.id).update(data);
      }
      if(mounted) Navigator.pop(context);
    } catch(e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"))); } 
    finally { if(mounted) setState(()=>_load=false); }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.product == null ? "Tambah Produk" : "Edit Produk")), 
      body: _load ? const Center(child: CircularProgressIndicator()) : Padding(padding: const EdgeInsets.all(20), child: Form(key: _key, child: ListView(children: [
        GestureDetector(onTap: _pick, child: Container(
          height: 180, decoration: BoxDecoration(color: Colors.grey[200], border: Border.all(color: Colors.grey)), 
          child: _imgFile != null ? Image.file(_imgFile!, fit: BoxFit.cover) : (_existingImageUrl != null ? CemilkuyImage(imageUrl: _existingImageUrl!) : const Icon(Icons.camera_alt, size: 50))
        )),
        const SizedBox(height: 20),
        TextFormField(initialValue: _name, decoration: const InputDecoration(labelText: 'Nama'), onSaved: (v)=>_name=v!, validator: (v)=>v!.isEmpty?'Isi':null),
        DropdownButtonFormField(value: _cat, items: ['Pedas','Manis','Asin'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(), onChanged: (v)=>setState(()=>_cat=v.toString())),
        Row(children: [Expanded(child: TextFormField(initialValue: _price==0?'':_price.toString(), decoration: const InputDecoration(labelText: 'Harga'), keyboardType: TextInputType.number, onSaved: (v)=>_price=int.parse(v!))), const SizedBox(width: 10), Expanded(child: TextFormField(initialValue: _stock==0?'':_stock.toString(), decoration: const InputDecoration(labelText: 'Stok'), keyboardType: TextInputType.number, onSaved: (v)=>_stock=int.parse(v!)))]),
        
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Tanggal Produksi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 5),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(icon: const Icon(Icons.calendar_today), label: Text(_prodDate == null ? "Pilih" : formatDate(_prodDate)), onPressed: () => _selectDate(true)))
          ])),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Tanggal Kadaluarsa", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
            const SizedBox(height: 5),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Colors.red), icon: const Icon(Icons.event_busy), label: Text(_expDate == null ? "Pilih" : formatDate(_expDate)), onPressed: () => _selectDate(false)))
          ])),
        ]),

        TextFormField(initialValue: _desc, decoration: const InputDecoration(labelText: 'Deskripsi'), maxLines: 2, onSaved: (v)=>_desc=v!),
        const SizedBox(height: 20), ElevatedButton(onPressed: _save, child: const Text("Simpan"))
      ]))));
  }
}