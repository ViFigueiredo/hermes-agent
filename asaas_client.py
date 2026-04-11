import requests
from datetime import datetime, timedelta

API_BASE = 'https://sandbox.asaas.com/api/v3'
API_KEY = '$aact_hmlg_000MzkwODA2MWY2OGM3MWRlMDU2NWM3MzJlNzZmNGZhZGY6OjIwNDQ0ODBjLTY5ZDEtNDY1Zi1iNDNjLTdhOTE2ZTkyOTdjYjo6JGFhY2hfM2MwODIxZjYtMWI1OC00YTNiLTk0YTctMGNiNzczNTQ0ODdl'

# --- Helpers ---
def request_asaas(method, endpoint, **kwargs):
    url = f'{API_BASE}{endpoint}'
    headers = kwargs.pop('headers', {})
    headers['access_token'] = API_KEY  # com $ no início
    response = requests.request(method, url, headers=headers, **kwargs)
    try:
        response.raise_for_status()
    except Exception as e:
        print(f'Erro ({response.status_code}): {response.text}')
        raise
    return response.json()

# --- Funções de cliente/pagamento PIX ---
def criar_cliente(nome, email, cpfCnpj=None, celular=None):
    data = {
        'name': nome,
        'email': email,
        'cpfCnpj': cpfCnpj or '12345678909',
        'mobilePhone': celular or '5511999999999',  # Corrigido para formato internacional
    }
    return request_asaas('POST', '/customers', json=data)

def criar_cobranca_pix(cliente_id, valor, vencimento, descricao='Teste PIX Hermes/Asaas'):
    data = {
        'customer': cliente_id,
        'value': valor,
        'dueDate': vencimento,
        'description': descricao,
        'billingType': 'PIX'
    }
    return request_asaas('POST', '/payments', json=data)

def obter_pix_qrcode(payment_id):
    return request_asaas('GET', f'/payments/{payment_id}/pixQrCode')

def consultar_cobranca(cobranca_id):
    return request_asaas('GET', f'/payments/{cobranca_id}')

def consultar_saldo():
    return request_asaas('GET', '/finance/balance')

if __name__ == '__main__':
    # 1. Criar cliente sandbox
    cliente = criar_cliente('Cliente PIX Hermes', 'hermes-pix-teste@example.com')
    cliente_id = cliente.get('id')
    print('Cliente:', cliente)
    # 2. Criar cobrança PIX
    vencimento = (datetime.today()+timedelta(days=1)).strftime('%Y-%m-%d')
    cobranca = criar_cobranca_pix(cliente_id, 2.50, vencimento)
    payment_id = cobranca.get('id')
    print('Cobrança PIX:', cobranca)
    # 3. Obter QRCode PIX
    info_pix = obter_pix_qrcode(payment_id)
    print('PIX QRCODE:', info_pix)
    # 4. Consultar saldo
    saldo = consultar_saldo()
    print('Saldo da conta:', saldo)
    # 5. Consultar status da cobrança
    status = consultar_cobranca(payment_id)
    print('Status da cobrança:', status)
