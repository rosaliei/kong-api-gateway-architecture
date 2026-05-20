# ID Token vs. Access Token: ရှင်းလင်းချက် (The Difference Explained)

OIDC (OpenID Connect) နှင့် OAuth 2.0 ကို အသုံးပြုရာတွင် **ID Token** နှင့် **Access Token** တို့၏ ကွာခြားချက်ကို နားလည်ရန် အလွန်အရေးကြီးပါသည်။

---

## ၁။ လွယ်ကူသော ဥပမာ (A Simple Analogy)

* **ID Token သည် "နိုင်ငံကူးလက်မှတ် (Passport) သို့မဟုတ် မှတ်ပုံတင်" နှင့် တူပါသည်။**
  ၎င်းသည် **သင်မည်သူမည်ဝါဖြစ်သည် (Who you are)** ကို သက်သေပြပါသည်။ ဥပမာ - သင့်အမည်၊ အီးမေးလ်၊ မွေးသက္ကရာဇ် စသည်တို့ ပါဝင်သည်။
* **Access Token သည် "ဟိုတယ်အခန်းသော့ (Hotel Key Card) သို့မဟုတ် ကားပါကင်လက်မှတ်" နှင့် တူပါသည်။**
  ၎င်းသည် **သင်ဘာလုပ်ခွင့်ရှိသည် (What you are allowed to do)** ကို သက်သေပြပါသည်။ အခန်းသော့တွင် သင့်နာမည်မပါသော်လည်း၊ မည်သည့်အခန်းကို ဖွင့်ခွင့်ရှိသည်ကို ဟိုတယ်တံခါး (API) က သိပါသည်။

---

## ၂။ အဓိက ကွာခြားချက်များ (Key Differences)

| အကြောင်းအရာ | ID Token (Identity) | Access Token (Authorization) |
| :--- | :--- | :--- |
| **ရည်ရွယ်ချက် (Purpose)** | User ၏ အချက်အလက် (Identity) ကို ဖော်ပြရန် | API / Resource များအား ဝင်ရောက်သုံးစွဲခွင့် (Access) ရယူရန် |
| **သက်ဆိုင်သော စံသတ်မှတ်ချက် (Standard)** | OpenID Connect (OIDC) | OAuth 2.0 |
| **အသုံးပြုသူ (Intended Audience)** | **Client Application** (ဥပမာ - Web UI, Mobile App) က ဖတ်ရန်ဖြစ်သည်။ | **Resource Server / API Gateway** (ဥပမာ - Kong, Payments API) က ဖတ်ရန်ဖြစ်သည်။ |
| **Format (ပုံစံ)** | အမြဲတမ်း **JWT (JSON Web Token)** ပုံစံဖြင့်သာ ရှိရမည်။ | JWT ဖြစ်နိုင်သလို၊ Opaque String (ကျပန်းစာသား) လည်း ဖြစ်နိုင်သည်။ (Keycloak တွင်မူ JWT ဖြင့်ထုတ်ပေးလေ့ရှိသည်) |
| **အဓိက ပါဝင်သော အချက်များ (Key Claims)** | `name`, `email`, `sub` (User ID), `picture`, `auth_time` | `scope`, `roles`, `azp` (Authorized Party) |
| **ဘယ်လိုသုံးလဲ? (How is it used?)** | App တွင် "Welcome, Mg Mg" ဟု ပြသရန်နှင့် User login ဝင်ထားကြောင်း သိရန်။ | API ခေါ်ဆိုရာတွင် `Authorization: Bearer <Access_Token>` အဖြစ် ထည့်သွင်းပေးပို့ရန်။ |

---

## ၃။ Client နှင့် API ရှုထောင့်မှ ကြည့်လျှင် (From the Perspective of Client and API)

### 🔴 အမှားများ (Common Mistakes)
* **Access Token ကို Client (Web App) မှ ဖတ်ပြီး User Info ကို ယူခြင်း။**
  Access Token သည် API အတွက်သာ ရည်ရွယ်သည်။ Client App သည် ၎င်းကို ဖတ်ရန်မလိုဘဲ API သို့ တိုက်ရိုက်သာ ပေးပို့သင့်သည်။ User Info ကို သိချင်လျှင် ID Token ကိုသာ ဖတ်ရမည်။
* **ID Token ကို API ခေါ်ဆိုရာတွင် အသုံးပြုခြင်း (Sending ID Token to APIs)။**
  ID Token တွင် API အတွက် လိုအပ်သော ခွင့်ပြုချက် (Permissions/Scopes) များ မပါဝင်ပါ။ ထို့ကြောင့် `Authorization` header တွင် ID Token ကို ထည့်မသုံးရပါ။ (ID Token ဖြင့် API ကို ခေါ်ဆို၍မရပါ)

### 🟢 မှန်ကန်သော အသုံးပြုပုံ (Correct Usage)
၁။ **User (သို့မဟုတ် Client)** သည် Keycloak (IdP) သို့ Login ဝင်သည်။
၂။ **Keycloak** သည် `ID Token` နှင့် `Access Token` နှစ်ခုစလုံးကို ပြန်ပေးသည်။
၃။ **Client App (Frontend)** သည် `ID Token` ကိုဖတ်၍ User ၏ အမည်၊ ပုံ စသည်တို့ကို UI တွင် ပြသသည်။
၄။ **Client App** သည် Kong / API သို့ Request ပို့သောအခါ `Access Token` ကိုသာ `Authorization: Bearer <token>` header တွင် ထည့်ပို့သည်။
၅။ **Kong (API Gateway)** သည် `Access Token` ကို စစ်ဆေးပြီး (ဥပမာ - `azp` ကိုစစ်ပြီး Consumer သတ်မှတ်ကာ) ခွင့်ပြုချက်ရှိ/မရှိ ဆုံးဖြတ်သည်။

---

## ၄။ ခြုံငုံသုံးသပ်ချက် (Summary)
* **ID Token** = `OIDC` ၏ ရလဒ်။ **Client** အတွက်ဖြစ်သည်။ **Identity (မည်သူမည်ဝါဖြစ်ကြောင်း)** ကိုဖော်ပြသည်။
* **Access Token** = `OAuth 2.0` ၏ ရလဒ်။ **API** အတွက်ဖြစ်သည်။ **Permission (ခွင့်ပြုချက်)** ကိုဖော်ပြသည်။
